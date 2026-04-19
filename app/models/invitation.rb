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

  scope :pending, -> { where(status: "pending").where("expires_at > ?", Time.current) }
  scope :expired, -> { where(status: "pending").where("expires_at <= ?", Time.current) }

  def self.bulk_invite!(workspace:, emails:, role:, invited_by:)
    sent = 0
    skipped = 0

    emails.each do |email|
      normalized = email.downcase

      unless normalized.match?(User::EMAIL_FORMAT)
        skipped += 1
        next
      end

      if workspace.memberships.kept.joins(:user).where(users: { email_address: normalized }).exists?
        skipped += 1
        next
      end

      if workspace.invitations.pending.where(email: normalized).exists?
        skipped += 1
        next
      end

      invitation = workspace.invitations.create!(
        email: normalized,
        role: role,
        invited_by: invited_by,
        expires_at: 7.days.from_now
      )
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

  def expired?
    expires_at <= Time.current
  end

  def magic_link?
    email.nil?
  end

  private

  def broadcast_target
    invitable_type == "Project" ? invitable.workspace : invitable
  end

  def accept_workspace_invitation!(user)
    existing = invitable.memberships.find_by(user: user)
    if existing&.discarded?
      existing.undiscard!
    elsif existing && !existing.discarded?
      raise ActiveRecord::RecordInvalid.new(self), "User is already a member"
    else
      invitable.memberships.create!(user: user, role: role)
    end
  end

  def accept_project_invitation!(user)
    workspace = invitable.workspace

    existing_membership = workspace.memberships.find_by(user: user)
    if existing_membership&.discarded?
      existing_membership.undiscard!
    elsif existing_membership.nil?
      workspace.memberships.create!(user: user, role: role)
    end

    raise ActiveRecord::RecordInvalid.new(self), "Project is no longer active" if invitable.discarded?
    raise ActiveRecord::RecordInvalid.new(self), "User is already a project member" if invitable.project_memberships.exists?(user: user)
    invitable.project_memberships.create!(user: user, role: project_role || "editor")
  end

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end
end
