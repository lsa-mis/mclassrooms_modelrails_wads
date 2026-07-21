class Invitation < ApplicationRecord
  class NotAcceptable < StandardError; end
  # Raised when an invitation addressed to a specific email is consumed by a
  # caller whose proven email differs. Subclasses NotAcceptable so existing
  # boundary rescues keep working, while callers that care can distinguish a
  # wrong-address attempt from a stale/used invitation for messaging.
  class EmailMismatch < NotAcceptable; end

  belongs_to :invitable, polymorphic: true
  belongs_to :role, optional: true
  belongs_to :invited_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true

  include Trackable
  include Broadcastable

  enum :status, { pending: "pending", accepted: "accepted", declined: "declined", revoked: "revoked" }, default: "pending"

  validates :role, presence: true
  validates :invited_by, presence: true
  validates :expires_at, presence: true
  validates :email, format: { with: User::EMAIL_FORMAT }, allow_nil: true

  before_create :generate_token

  # Notifier triggers: fire on the accepted/declined transitions only.
  # `<attr>_previously_changed?` is true exclusively in the after_update_commit
  # phase of the update that wrote the new value, so we get one notification
  # per state transition (never on subsequent unrelated updates).
  after_update_commit :notify_accepted, if: :just_accepted?
  after_update_commit :notify_declined, if: :just_declined?

  scope :pending, -> { where(status: "pending").where("expires_at > ?", Time.current) }
  scope :expired, -> { where(status: "pending").where("expires_at <= ?", Time.current) }

  # Composed scope used by Workspaces::MembersController#index. Pending
  # invitations are excluded entirely when the status filter selects a
  # membership-only state (active or deactivated). Sort direction comes
  # from the page's column-sort UI but invitations have no full_name,
  # so the email column carries the sort if any.
  scope :for_members_index, ->(q:, role:, status:) {
    return none if %w[active deactivated].include?(status)

    scope = pending.includes(:role)
    # Escape LIKE wildcards (%, _) so they match literally, mirroring
    # Membership.search — otherwise a query like "a_b" matches "axb" too.
    if q.present?
      sanitized = sanitize_sql_like(q.to_s.downcase)
      scope = scope.where("LOWER(email) LIKE :q ESCAPE '\\'", q: "%#{sanitized}%")
    end
    scope = scope.joins(:role).where(roles: { slug: role }) if role.present?
    scope
  }

  def self.bulk_invite!(workspace:, emails:, role:, invited_by:)
    sent = 0
    skipped = 0

    # Preload existing members and pending invitations to avoid N+1 queries
    existing_members = workspace.memberships.kept.joins(:user)
      .pluck("LOWER(users.email_address)").to_set
    existing_invites = workspace.invitations.pending
      .where.not(email: nil).pluck(:email).map(&:downcase).to_set

    emails.each do |email|
      normalized = email.downcase

      unless normalized.match?(User::EMAIL_FORMAT)
        skipped += 1
        next
      end

      if existing_members.include?(normalized) || existing_invites.include?(normalized)
        skipped += 1
        next
      end

      begin
        invitation = workspace.invitations.create!(
          email: normalized,
          role: role,
          invited_by: invited_by,
          expires_at: 7.days.from_now
        )
      rescue ActiveRecord::RecordNotUnique
        # Concurrent request won the race to the pending-invite partial unique
        # index after our preload; that invite already exists and was mailed.
        skipped += 1
        next
      end
      existing_invites.add(normalized)
      InvitationMailer.invite(invitation).deliver_later
      sent += 1
    end

    { sent: sent, skipped: skipped }
  end

  # Shared consumption core for both signup acceptance paths: the session-based
  # one (Signupable#accept_pending_invitation!) and the column-based one
  # (Authentication#claim_pending_invitation!). Centralizing it keeps both flows
  # on identical acceptance semantics. Returns the invitation on success, or nil
  # when the token is blank or matches nothing. Propagates Invitation::NotAcceptable
  # when the invitation exists but is no longer acceptable, so callers can surface
  # the race; #accept! still owns the pessimistic lock and state transition.
  def self.consume!(token:, user:, expected_email: nil)
    return if token.blank?

    invitation = find_by(token: token)
    return if invitation.nil?

    # Email-match guard: when an invitation is addressed to a specific email,
    # only consume it for a caller whose proven email matches. This is what
    # closes bearer-token redemption — combined with deferring consumption to
    # email verification, a leaked link can't be claimed from a different
    # (even verified) address. Magic-link invitations (nil email) stay bearer
    # by design; direct callers that pass no expected_email skip the check.
    if invitation.email.present? && expected_email.present? &&
        !EmailNormalizer.equivalent?(invitation.email, expected_email)
      raise EmailMismatch
    end

    invitation.accept!(user)
    invitation
  end

  def accept!(user)
    transaction do
      lock!
      raise NotAcceptable, "Invitation no longer acceptable" unless pending?
      raise NotAcceptable, "Invitation no longer acceptable" if expired?
      # Single choke point for the non-active-workspace gate: every
      # acceptance path (direct accept controller, magic-link registration,
      # OAuth signup, email-verification claim) funnels through accept!, so
      # guarding here — rather than in any one controller — closes all of
      # them at once. admittable? covers every non-active state (archived,
      # deleted, suspended) and fails closed when resolved_workspace is nil.
      # Reuses NotAcceptable's existing invalid/expired rejection copy
      # rather than the locked_notice copy: an invitee must not learn the
      # workspace is locked. This also makes Workspace#admit's own
      # NotAdmittableError raise unreachable from invitation flows; that
      # guard remains as a backstop for other admit callers (e.g. open-link
      # self-join).
      raise NotAcceptable, "Invitation no longer acceptable" unless resolved_workspace&.admittable?
      accept_workspace_invitation!(user)

      update!(
        status: "accepted",
        accepted_by: user,
        accepted_at: Time.current
      )
    end
  end

  def decline!
    raise ActiveRecord::RecordInvalid.new(self), "Invitation already processed" unless pending?
    update!(status: "declined", declined_at: Time.current)
  end

  def revoke!
    raise ActiveRecord::RecordInvalid.new(self), "Invitation already processed" unless pending?
    update!(status: "revoked", revoked_at: Time.current)
  end

  def resend!
    update!(
      token: SecureRandom.urlsafe_base64(32),
      expires_at: 7.days.from_now
    )
  end

  def acceptable?
    pending? && !expired?
  end

  def expired?
    expires_at <= Time.current
  end

  def magic_link?
    email.nil?
  end

  # Hours remaining until expiry, ceiled to the next whole hour. Single source
  # of truth for the user-facing "expires in N hours" copy in both the
  # WorkspaceInvitationExpiringSoonNotifier message and the matching mailer.
  # Ceil (not round/floor) so T-30min reads as "1 hour" not "0 hours" — the
  # message is hours-remaining, and rounding down to zero is misleading UX.
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

  def broadcast_target
    invitable
  end

  def accept_workspace_invitation!(user)
    # Delegate to the single membership-grant entry point. Locking, capacity,
    # discarded-reactivation, and :shared-posture role reconciliation all live
    # in Workspace#admit so the open-link self-join flow (Reshape 2) shares
    # identical semantics.
    invitable.admit(user, role: role)
  end

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end

  def just_accepted?
    accepted_at_previously_changed? && accepted_at.present?
  end

  def just_declined?
    declined_at_previously_changed? && declined_at.present?
  end

  def notify_accepted
    return if invited_by.blank?
    return if invited_by == accepted_by  # don't ping the inviter for their own acceptance
    WorkspaceInvitationAcceptedNotifier.with(record: self).deliver(invited_by)
  end

  # Mirror of notify_accepted's self-recipient guard. Decline has no accepted_by
  # column (declines come from email/magic-link, not a signed-in user), so the
  # check is "did the inviter decline their own invitation?" — compared via
  # EmailNormalizer.equivalent? to absorb case / Unicode-NFC / IDN punycode
  # variation between the stored invitation email and the inviter's address.
  def notify_declined
    return if invited_by.blank?
    return if EmailNormalizer.equivalent?(email, invited_by.email_address)
    WorkspaceInvitationDeclinedNotifier.with(record: self).deliver(invited_by)
  end
end
