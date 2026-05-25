class Invitation < ApplicationRecord
  belongs_to :invitable, polymorphic: true
  belongs_to :role
  belongs_to :invited_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true

  include Trackable
  include Broadcastable

  enum :status, { pending: "pending", accepted: "accepted", declined: "declined", revoked: "revoked" }, default: "pending"

  validates :role, presence: true
  validates :invited_by, presence: true
  validates :expires_at, presence: true
  validates :project_role, inclusion: { in: %w[editor viewer] }, allow_nil: true
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
    scope = scope.where("LOWER(email) LIKE ?", "%#{q.to_s.downcase}%") if q.present?
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

      invitation = workspace.invitations.create!(
        email: normalized,
        role: role,
        invited_by: invited_by,
        expires_at: 7.days.from_now
      )
      existing_invites.add(normalized)
      InvitationMailer.invite(invitation).deliver_later
      sent += 1
    end

    { sent: sent, skipped: skipped }
  end

  def accept!(user)
    transaction do
      lock!
      raise ActiveRecord::RecordInvalid.new(self), "Invitation already processed" unless pending?
      raise ActiveRecord::RecordInvalid.new(self), "Invitation expired" if expired?
      if invitable_type == "Project"
        accept_project_invitation!(user)
      else
        accept_workspace_invitation!(user)
      end

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

  # Resolves the workspace context for a polymorphic invitation. An invitation
  # may target a Workspace directly or a Project — in the latter case the
  # workspace context comes from the project. Single source of truth shared by
  # the notifiers (Accepted / Declined / ExpiringSoon) and NotificationMailer.
  def resolved_workspace
    case invitable
    when Workspace then invitable
    when Project   then invitable.workspace
    end
  end

  private

  def broadcast_target
    invitable_type == "Project" ? invitable.workspace : invitable
  end

  def accept_workspace_invitation!(user)
    invitable.lock!
    existing = invitable.memberships.find_by(user: user)
    if existing&.discarded?
      existing.undiscard!
    elsif existing && !existing.discarded?
      raise ActiveRecord::RecordInvalid.new(self), "User is already a member"
    else
      if invitable.memberships.kept.count >= invitable.max_members
        raise ActiveRecord::RecordInvalid.new(self), "Workspace is at capacity"
      end
      invitable.memberships.create!(user: user, role: role)
    end
  end

  def accept_project_invitation!(user)
    workspace = invitable.workspace
    workspace.lock!

    existing_membership = workspace.memberships.find_by(user: user)
    if existing_membership&.discarded?
      existing_membership.undiscard!
    elsif existing_membership.nil?
      if workspace.memberships.kept.count >= workspace.max_members
        raise ActiveRecord::RecordInvalid.new(self), "Workspace is at capacity"
      end
      workspace.memberships.create!(user: user, role: role)
    end

    raise ActiveRecord::RecordInvalid.new(self), "Project is no longer active" if invitable.discarded?
    raise ActiveRecord::RecordInvalid.new(self), "User is already a project member" if invitable.project_memberships.exists?(user: user)
    invitable.project_memberships.create!(user: user, role: project_role || "editor")
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
