class User < ApplicationRecord
  # Include order is callback registration order, kept as it was before the traits existed (Onboarding's
  # after_create ahead of Avatar's). No current callback depends on it; reorder with that in mind.
  include Onboarding
  include Avatar
  include Password
  include KnownDevices

  has_many :sessions, dependent: :destroy
  has_many :authentications, dependent: :destroy
  has_one :preferences, class_name: "UserPreferences", dependent: :destroy
  # delete_all, not destroy (#817): no FK backs this, so this line is the whole guard against orphan notification rows.
  has_many :notifications, as: :recipient, dependent: :delete_all, class_name: "Noticed::Notification"
  has_many :memberships, dependent: :destroy
  has_many :saved_rooms, dependent: :destroy
  # Kept memberships only (#931): a removed member must not resolve a workspace; `memberships` stays unscoped.
  # See /docs/developer/membership-lifecycle.
  has_many :active_memberships, -> { kept }, class_name: "Membership", inverse_of: :user
  has_many :workspaces, through: :active_memberships
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :invited_by_id, dependent: :destroy
  # accepted_by_id is nullable but carries a real FK — without this, #816's
  # fix above merely unmasks InvalidForeignKey on destroy.
  has_many :accepted_invitations, class_name: "Invitation", foreign_key: :accepted_by_id, dependent: :nullify
  has_many :invitation_blocks, foreign_key: :inviter_id, dependent: :delete_all
  has_many :webauthn_credentials, dependent: :destroy

  # Rails applies `normalizes` to find_by values too, so lookups get canonical matching for free.
  normalizes :email_address, with: ->(e) { EmailNormalizer.normalize(e) }
  normalizes :pending_email, with: ->(e) { EmailNormalizer.normalize(e) }
  # Encrypted at rest (#902). Declared after `normalizes` so the cipher wraps the normalized value;
  # `downcase:` covers the hole `normalizes` leaves, not a redundancy.
  encrypts :email_address, deterministic: true, downcase: true
  encrypts :pending_email, :first_name, :last_name

  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  validates :email_address, presence: true, uniqueness: true,
                            format: { with: EMAIL_FORMAT }
  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, presence: true, length: { maximum: 100 }

  validates :pending_email, format: { with: EMAIL_FORMAT }, allow_blank: true
  validate :pending_email_not_taken, if: -> { pending_email.present? }

  def full_name
    "#{first_name} #{last_name}"
  end

  def initials
    parts = [ first_name, last_name ].map(&:to_s).reject(&:blank?)
    return "?" if parts.empty?
    parts.map { |p| p[0].upcase }.join
  end

  def email_verification_pending?
    authentications.email.pending.exists?
  end

  # create_or_find_by!: a racing insert loses on the unique index and returns the winner's row (#884).
  def preferences!
    preferences || UserPreferences.create_or_find_by!(user: self).tap { |row| association(:preferences).target = row }
  end

  # Proven addresses only: every verified_at writer must be in spec/requests/can_invite_gate_spec.rb's inventory.
  # See /docs/developer/security (Verified addresses gate invitations).
  def can_invite?
    authentications.where.not(verified_at: nil).exists?
  end

  def identity
    UserIdentity.new(self)
  end

  def available_reauth_factors
    factors = []
    factors << :password if has_password?
    factors << :passkey if webauthn_credentials.kept.any?
    factors << :email
    factors
  end

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

  def pending_email_not_taken
    if User.where.not(id: id).exists?(email_address: pending_email)
      errors.add(:pending_email, :taken)
    end
  end
end
