class User < ApplicationRecord
  has_secure_password validations: false

  has_many :sessions, dependent: :destroy
  has_many :authentications, dependent: :destroy
  has_one :preferences, class_name: "UserPreferences", dependent: :destroy
  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"
  has_one_attached :avatar
  has_one_attached :avatar_original
  has_many :memberships, dependent: :destroy
  has_many :saved_rooms, dependent: :destroy
  has_many :workspaces, through: :memberships
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :invited_by_id, dependent: :nullify
  has_many :webauthn_credentials, dependent: :destroy

  after_create :onboard_workspace
  after_create :check_gravatar_later
  after_update_commit :check_gravatar_later, if: :saved_change_to_email_address?
  # Model-level so every digest-touching path notifies (settings change, reset,
  # removal) — the behavior app/docs/developer/notifications.md documents.
  after_update_commit :notify_password_changed, if: :saved_change_to_password_digest?
  # Strict tier (notifications lifecycle arc): the audit row commits or the
  # credential write doesn't — deliberate evidence-over-availability trade
  # (a rollback here also leaves other sessions alive; they die with the
  # retried rotation). notify_password_changed above stays after_update_COMMIT
  # — it enqueues into the Solid Queue SQLite file, and pulling that inside
  # the primary write lock is a cross-database lock-ordering hazard against
  # queue workers.
  after_update :audit_password_digest_change, if: :saved_change_to_password_digest?

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
    content_type: IMAGE_CONTENT_TYPES,
    size: { less_than: 5.megabytes }
  validates :avatar_original,
    content_type: IMAGE_CONTENT_TYPES,
    size: { less_than: 10.megabytes }
  validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true

  MAX_FAILED_ATTEMPTS = 5
  LOCK_DURATION = 1.hour
  MAX_KNOWN_BROWSERS = 20

  # Single source of truth for the (user_agent, os) -> digest formula used by
  # the new-device sign-in detector. Public so SignInFromNewDeviceNotifier's
  # `populate_idempotency_key` override can reuse the same formula — keeping
  # the User-side fingerprint and the Notifier-side dedup key in lockstep.
  # Version segments are stripped before hashing so routine browser updates
  # (Chrome/126 -> 127, iOS 17_5 -> 17_5_1) don't re-fire the detector — the
  # goal is "alert on an unfamiliar device", and a device that auto-updated
  # its browser is not unfamiliar. See #seen_browser?.
  def self.browser_digest(user_agent, os)
    Digest::SHA256.hexdigest("#{user_agent.to_s.gsub(/[\d_.]+/, "")} #{os}")
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

  # Tears down password authentication as one unit: email authentications, the
  # digest itself, and whatever the caller needs committed with them (session
  # revocation). Returns whether this caller performed the removal.
  #
  # The reload is the concurrency guard (#826). A second request that loaded
  # this user before the first removal committed still holds the old digest in
  # memory, so its update! issues a real UPDATE, satisfies
  # saved_change_to_password_digest?, and writes a second user.password_removed
  # row. Re-reading inside the transaction — where the write lock is already
  # held, so the read is current — makes the second caller a no-op instead.
  #
  # update! rather than update_columns: the strict audit callback and the
  # post-commit notifier both have to fire, and update_columns silently skipped
  # both (#813).
  def remove_password!
    transaction do
      reload
      next false if password_digest.nil?

      authentications.email.destroy_all
      # save! rather than update!: validate: false drops full-record
      # validation, so a record that drifted invalid for reasons unrelated to
      # credentials (an attachment allowlist tightening, say) cannot hold the
      # removal hostage. Callbacks still run — the strict audit row and the
      # post-commit notifier are the point of using the callback path (#820).
      self.password_digest = nil
      save!(validate: false)
      yield if block_given?
      true
    end
  end

  def has_password?
    password_digest.present?
  end

  # Sending invitations requires a PROVEN address. Every authentication whose
  # verified_at is set got there by demonstrating control of the mailbox —
  # clicking a signed link sent to it (Authentication#verify!, magic-link
  # callback) or a provider vouching for it (OauthLink, gated on
  # identity.email_verified?). The one writer that proved nothing was
  # Settings::PasswordsController#create, which stamped verified_at on a
  # freshly-minted email authentication: setting a password demonstrates
  # control of the SESSION, not of the address. That stamp is gone, which is
  # what lets this predicate stay a simple existence check.
  #
  # If you add a verified_at writer, add it to the inventory in
  # spec/requests/can_invite_gate_spec.rb — the gate is only as strong as the
  # weakest path that sets the column.
  def can_invite?
    authentications.where.not(verified_at: nil).exists?
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

  def identity
    UserIdentity.new(self)
  end

  # Factors this user can prove for re-authentication. The interstitial view
  # and the reauthentication controller both read this so they can't diverge on
  # which factors are on offer. Email is always available as the fallback.
  def available_reauth_factors
    factors = []
    factors << :password if has_password?
    factors << :passkey if webauthn_credentials.kept.any?
    factors << :email
    factors
  end

  # Browser-fingerprint heuristic for the new-device sign-in detector.
  # Digest is intentionally coarse (version-stripped — see .browser_digest) so
  # the same browser/OS combo across UA version bumps still matches "seen".
  # The goal is "alert on unfamiliar device", not forensic device tracking.
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
      # Bounded: this JSON column is read and rewritten on the sign-in hot
      # path (SQLite single writer), so it must not grow with UA churn.
      if browsers.size > MAX_KNOWN_BROWSERS
        browsers = browsers.sort_by { |e| e["last_seen_at"] }.last(MAX_KNOWN_BROWSERS)
      end
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
  # Used by UnreadNotificationSummary to compute count and severity in one DB hit.
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

  # Runs the HIBP range check NOW — outside any transaction — and memoizes the
  # result per password value; the validation then consumes the memo instead of
  # doing network I/O inside BEGIN IMMEDIATE (SQLite's database-wide write
  # lock — #674). Controllers that accept a password call this between
  # assign_attributes and save. An unprechecked save still checks live as a
  # fallback, bounded by the initializer timeouts.
  def precheck_password_pwned!
    return if password.blank?
    @pwned_precheck = [ password, password_pwned_now? ]
    nil
  end

  private

  def check_gravatar_later
    CheckGravatarJob.perform_later(self)
  end

  def audit_password_digest_change
    ActivityLog.record_security_event!(
      action: password_digest.nil? ? "user.password_removed" : "user.password_changed",
      user: self
    )
  end

  # Best-effort: the security alert must never fail the credential write
  # itself (same contract as the new-device hook in Authenticatable).
  def notify_password_changed
    PasswordChangedNotifier.with(record: self, removed: password_digest.nil?).deliver(self)
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[password-changed] swallowed error for user=#{id}: #{e.class}: #{e.message}")
  end

  # Dispatches to the right onboarding strategy based on the tenancy preset.
  # See app/docs/developer/presets.md for the contract.
  def onboard_workspace
    case TenancyConfig.onboarding
    when :personal then create_personal_workspace
    when :shared   then join_shared_workspace
    when :none     then skip_workspace_creation
    end
  end

  def skip_workspace_creation
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
    pwned =
      if @pwned_precheck && @pwned_precheck[0] == password
        @pwned_precheck[1]
      else
        password_pwned_now?
      end
    errors.add(:password, :pwned) if pwned
  end

  def password_pwned_now?
    Pwned::Password.new(password).pwned?
  rescue Pwned::Error
    # Network error — allow password (don't block registration on external service failure)
    false
  end

  def pending_email_not_taken
    if User.where.not(id: id).exists?(email_address: pending_email)
      errors.add(:pending_email, :taken)
    end
  end
end
