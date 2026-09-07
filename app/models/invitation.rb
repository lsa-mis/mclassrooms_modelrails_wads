class Invitation < ApplicationRecord
  class NotAcceptable < StandardError; end
  # Subclasses NotAcceptable so boundary rescues keep working; callers that care can still tell a wrong address apart.
  class EmailMismatch < NotAcceptable; end

  belongs_to :invitable, polymorphic: true
  belongs_to :role, optional: true
  belongs_to :invited_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true

  include Trackable
  include Broadcastable
  include Suppression
  include Issuance
  include Acceptance

  enum :status, { pending: "pending", accepted: "accepted", declined: "declined", revoked: "revoked" }, default: "pending"

  validates :role, presence: true
  validates :invited_by, presence: true
  validates :expires_at, presence: true
  # `|| e`: a blank string must fail the format check, never become nil — nil means a bearer magic-link invitation.
  normalizes :email, with: ->(e) { EmailNormalizer.normalize(e) || e }
  # Encrypted at rest (#902); deterministic because the pending-live unique index and bulk_invite! look up by email.
  encrypts :email, deterministic: true, downcase: true
  # Rebuilt into URLs later (reminder, notification mailer), so it can't be a
  # digest; deterministic keeps find_by/the index working (#953). No downcase: base64.
  encrypts :token, deterministic: true
  validates :email, format: { with: User::EMAIL_FORMAT }, allow_nil: true

  before_create :generate_token

  # `_previously_changed?` is true only in the writing update's commit phase — one notification per transition.
  after_update_commit :notify_accepted, if: :just_accepted?
  after_update_commit :notify_declined, if: :just_declined?

  # Not named `pending` (#452): overriding the enum's scope desyncs it from the `pending?` predicate.
  scope :acceptable, -> { where(status: "pending").where("expires_at > ?", Time.current) }
  scope :expired, -> { where(status: "pending").where("expires_at <= ?", Time.current) }

  # Mirror of Membership.for_members_index; the two split one status filter — keep them in sync.
  scope :for_members_index, ->(role:, status:) {
    return none if %w[active deactivated].include?(status)

    scope = acceptable.includes(:role)
    scope = scope.joins(:role).where(roles: { slug: role }) if role.present?
    scope
  }

  def decline!
    while_still_pending! { update!(status: "declined", declined_at: Time.current) }
  end

  def revoke!
    while_still_pending! { update!(status: "revoked", revoked_at: Time.current) }
  end

  def resend!
    while_still_pending! do
      update!(
        token: SecureRandom.urlsafe_base64(32),
        expires_at: 7.days.from_now
      )
    end
  end

  def acceptable? = pending? && !expired?

  def expired? = expires_at <= Time.current

  def magic_link? = email.nil?

  # Nothing to deliver to on a magic link — a false here is NOT a block, so a
  # future magic-link mailer must not read it as one (PR 4 spec §2).
  def has_invitee? = !magic_link?

  # Ceil, not round: T-30min must read "1 hour". Single source for the notifier and its mailer.
  def expires_in_hours
    return 0 if expires_at <= Time.current
    ((expires_at - Time.current) / 1.hour).ceil
  end

  # Resolves the workspace context for an invitation. Workspace is currently
  # the only invitable type (Project invites were removed with the example
  # domain). Single source of truth shared by the notifiers (Accepted /
  # Declined / ExpiringSoon) and NotificationMailer.
  def resolved_workspace
    invitable if invitable.is_a?(Workspace)
  end

  private

  # The bang is the raise: the block runs only if this invitation is still pending once locked, else
  # RecordInvalid with :already_processed on errors[:base], which the four rescuing controllers render.
  # lock! reloads inside BEGIN IMMEDIATE, so a stale pending? can't overwrite a committed acceptance (#675).
  # Acceptance#accept! keeps its own shape on purpose: its guard is acceptable? (pending, unexpired,
  # admittable) and its exception is NotAcceptable, which the accept controllers rescue by name.
  # See /docs/developer/architecture (Concurrency).
  def while_still_pending!
    transaction do
      lock!
      unless pending?
        errors.add(:base, :already_processed)
        raise ActiveRecord::RecordInvalid, self
      end
      yield
    end
  end

  def broadcast_target
    resolved_workspace
  end

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end

  # Never the ambient Current.workspace — acceptance can happen from another workspace's page.
  def activity_workspace
    resolved_workspace
  end

  def just_accepted?
    accepted_at_previously_changed? && accepted_at.present?
  end

  def just_declined?
    declined_at_previously_changed? && declined_at.present?
  end

  def notify_accepted
    return if invited_by.blank?
    return if invited_by == accepted_by
    WorkspaceInvitationAcceptedNotifier.with(record: self).deliver(invited_by)
  end

  # Decline has no accepted_by; compare addresses with EmailNormalizer.equivalent? to absorb case/NFC/punycode variation.
  def notify_declined
    return if invited_by.blank?
    return if EmailNormalizer.equivalent?(email, invited_by.email_address)
    WorkspaceInvitationDeclinedNotifier.with(record: self).deliver(invited_by)
  end
end
