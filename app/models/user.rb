class User < ApplicationRecord
  has_secure_password validations: false
  attr_accessor :current_password

  has_many :sessions, dependent: :destroy
  has_many :authentications, dependent: :destroy
  has_one :preferences, class_name: "UserPreferences", dependent: :destroy
  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"
  has_one_attached :avatar
  has_one_attached :avatar_original
  has_many :memberships, dependent: :destroy
  has_many :workspaces, through: :memberships
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :invited_by_id, dependent: :nullify
  has_many :webauthn_credentials, dependent: :destroy

  after_create :onboard_workspace
  after_create :check_gravatar_later
  after_update_commit :check_gravatar_later, if: :saved_change_to_email_address?

  # Canonical email storage and lookup: NFC + downcase + strip via EmailNormalizer.
  # Rails 7.1+ also applies these normalizers to `find_by(email_address:)` and
  # `find_by(pending_email:)` lookup values, so callsites passing user input
  # directly into find_by automatically benefit from the same normalization.
  normalizes :email_address, with: ->(e) { EmailNormalizer.normalize(e) }
  normalizes :pending_email, with: ->(e) { EmailNormalizer.normalize(e) }

  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  validates :email_address, presence: true, uniqueness: true,
                            format: { with: EMAIL_FORMAT }
  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, presence: true, length: { maximum: 100 }
  validates :password, length: { minimum: 12 }, if: -> { password.present? && (password_digest_changed? || new_record?) }
  validates :password, confirmation: true, if: -> { password.present? }
  validate :password_not_pwned, if: -> { password.present? && (password_digest_changed? || new_record?) }

  validates :pending_email, format: { with: EMAIL_FORMAT }, allow_blank: true
  validate :pending_email_not_taken, if: -> { pending_email.present? }
  validates :avatar_source, inclusion: { in: %w[upload gravatar initials] }
  validates :avatar,
    content_type: %w[image/png image/jpeg image/gif image/webp],
    size: { less_than: 5.megabytes }
  validates :avatar_original,
    content_type: %w[image/png image/jpeg image/gif image/webp],
    size: { less_than: 10.megabytes }
  validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true

  MAX_FAILED_ATTEMPTS = 5
  LOCK_DURATION = 1.hour

  # Single source of truth for the (user_agent, os) -> digest formula used by
  # the new-device sign-in detector. Public so SignInFromNewDeviceNotifier's
  # `populate_idempotency_key` override can reuse the same formula — keeping
  # the User-side fingerprint and the Notifier-side dedup key in lockstep.
  # Intentionally coarse (no salt, no normalization) — see #seen_browser?.
  def self.browser_digest(user_agent, os)
    Digest::SHA256.hexdigest("#{user_agent} #{os}")
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def initials
    parts = [ first_name, last_name ].map(&:to_s).reject(&:blank?)
    return "?" if parts.empty?
    parts.map { |p| p[0].upcase }.join
  end

  # True iff the user has an email sign-in awaiting verification. Existence
  # check (Authentication's own email/pending scopes) so the layout banner
  # that renders on every authenticated page doesn't instantiate a record.
  def email_verification_pending?
    authentications.email.pending.exists?
  end

  def onboarded?
    onboarded_at.present?
  end

  # First-run wizard helper (:none posture). The wizard has a single step —
  # create a workspace — so the only derived state is "has one or not".
  def onboarding_workspace
    workspaces.kept.first
  end

  def onboarding_step
    :workspace
  end

  def locked?
    return false if locked_at.nil?
    locked_at > LOCK_DURATION.ago
  end

  def register_failed_login!
    increment!(:failed_login_attempts)
    update!(locked_at: Time.current) if failed_login_attempts >= MAX_FAILED_ATTEMPTS
  end

  def register_successful_login!
    update!(failed_login_attempts: 0, locked_at: nil)
  end

  def has_password?
    password_digest.present?
  end

  def gravatar_url(size: 128)
    return nil if email_address.blank?

    hash = Digest::SHA256.hexdigest(EmailNormalizer.normalize(email_address))
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=404"
  end

  def available_avatar_sources
    sources = %w[upload initials]
    sources << "gravatar" if has_gravatar?
    sources
  end

  def initiate_email_change!(new_email, password)
    return false unless has_password?
    return false unless authenticate(password)

    normalized = EmailNormalizer.normalize(new_email)
    return false if EmailNormalizer.equivalent?(normalized, email_address)

    self.pending_email = new_email
    self.pending_email_token = SecureRandom.urlsafe_base64(32)
    self.pending_email_sent_at = Time.current

    save
  end

  def confirm_email_change!(token)
    return false if token.blank?

    transaction do
      reload
      return false if pending_email_token != token
      return false unless pending_email_token_valid?

      self.email_address = pending_email
      clear_pending_email_fields
      save!

      authentications.email.update_all(uid: email_address)
    end

    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def cancel_email_change!
    clear_pending_email_fields
    save!
  end

  def pending_email_token_valid?
    pending_email_token.present? &&
      pending_email_sent_at.present? &&
      pending_email_sent_at > 24.hours.ago
  end

  # Browser-fingerprint heuristic for the new-device sign-in detector.
  # Digest is intentionally coarse — `SHA256("#{user_agent} #{os}")` — so the
  # same browser/OS combo across minor UA bumps still matches "seen". The goal
  # is "alert on unfamiliar device", not forensic device tracking.
  def seen_browser?(user_agent, os)
    digest = self.class.browser_digest(user_agent, os)
    last_known_browsers.any? { |entry| entry["digest"] == digest }
  end

  # Records or refreshes a (ua, os) fingerprint on the user. New entries get a
  # `first_seen_at`; subsequent records of the same digest only bump
  # `last_seen_at`. Persists via update_column to bypass validation/touch on a
  # post-sign-in hot path. Times are stored as ISO-8601 strings for stable
  # serialization round-trips through the JSON column.
  def record_browser!(user_agent, os)
    digest = self.class.browser_digest(user_agent, os)
    now = Time.current
    browsers = last_known_browsers.dup
    if (entry = browsers.find { |e| e["digest"] == digest })
      entry["last_seen_at"] = now.iso8601
    else
      browsers << {
        "digest" => digest,
        "first_seen_at" => now.iso8601,
        "last_seen_at" => now.iso8601
      }
    end
    update_column(:last_known_browsers, browsers)
  end

  # Resolves the user's personal workspace via the denormalized FK column
  # (users.personal_workspace_id), backed by a unique partial index that
  # enforces "at most one personal workspace per user" at the database level.
  # Returns nil if the FK is unset or the referenced workspace was discarded.
  def personal_workspace
    return nil if personal_workspace_id.nil?
    Workspace.kept.find_by(id: personal_workspace_id)
  end

  # Returns { notifier_class_name => unread_count, ... } for the user.
  # Used by NotificationBellHelper to compute count and severity in one DB hit.
  def unread_notification_breakdown
    notifications
      .where(read_at: nil)
      .joins("INNER JOIN noticed_events ON noticed_events.id = noticed_notifications.event_id")
      .group("noticed_events.type")
      .count
  end

  # True iff the one-time passkey enrollment banner should appear.
  # Clears once the user dismisses the banner OR registers a passkey.
  def passkey_prompt_eligible?
    passkey_prompt_seen_at.nil? && webauthn_credentials.kept.none?
  end

  # Opaque, stable WebAuthn user handle — never the integer PK (FIDO guidance).
  # Lazily generated on first enrollment; race-safe via the unique index + retry.
  def webauthn_handle!
    return webauthn_handle if webauthn_handle.present?
    update!(webauthn_handle: SecureRandom.urlsafe_base64(32))
    webauthn_handle
  rescue ActiveRecord::RecordNotUnique
    reload.webauthn_handle
  end

  private

  def check_gravatar_later
    CheckGravatarJob.perform_later(self)
  end

  # Dispatches to the right onboarding strategy based on the tenancy preset.
  # See app/docs/developer/presets.md for the contract.
  def onboard_workspace
    case TenancyConfig.onboarding
    when :personal then create_personal_workspace
    when :shared   then join_shared_workspace
    when :none     then nil # explicit: :none creates no workspace; the user's home is workspace-agnostic (see config/initializers/tenancy.rb)
    end
  end

  def create_personal_workspace
    return if personal_workspace_id.present?

    workspace = Workspace.create!(name: "#{first_name}'s Workspace", personal: true)
    owner_role = Role.system_default!("owner")
    workspace.memberships.create!(user: self, role: owner_role)
    update_column(:personal_workspace_id, workspace.id)
  end

  # Fork deviation (MiClassrooms Task 4): the self-onboarding role below was
  # hardcoded "member"; it now reads TenancyConfig.shared_join_role.
  # :shared posture: every new user joins the configured shared workspace, in
  # the role given by TenancyConfig.shared_join_role (default "member" — the
  # template's original hardcoded self-onboarding role; a fork can override
  # via TENANCY_SHARED_JOIN_ROLE, e.g. MiClassrooms uses "viewer" so signups
  # land read-only). No personal workspace is created. Owners + Admins are
  # seeded/promoted separately (see db/seeds.rb).
  def join_shared_workspace
    workspace = TenancyConfig.shared_workspace
    raise "Shared workspace #{TenancyConfig.shared_workspace_slug.inspect} not found — has the tenancy seed run?" unless workspace
    # A non-admittable shared workspace (suspended = instance maintenance/hold;
    # archived/deleted shouldn't happen to the shared home workspace, but
    # admittable? fails closed regardless) — the account still creates (this
    # runs in the after_create transaction; a raise would roll back
    # registration), the user simply joins nothing and lands on the empty index.
    return unless workspace.admittable?

    join_role = Role.system_default!(TenancyConfig.shared_join_role)
    workspace.memberships.create!(user: self, role: join_role)
  end

  def password_not_pwned
    return if password.blank?
    if Pwned::Password.new(password).pwned?
      errors.add(:password, :pwned)
    end
  rescue Pwned::Error
    # Network error — allow password (don't block registration on external service failure)
  end

  def pending_email_not_taken
    if User.where.not(id: id).exists?(email_address: pending_email)
      errors.add(:pending_email, :taken)
    end
  end

  def clear_pending_email_fields
    self.pending_email = nil
    self.pending_email_token = nil
    self.pending_email_sent_at = nil
  end
end
