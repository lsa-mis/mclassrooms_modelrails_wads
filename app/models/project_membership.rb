class ProjectMembership < ApplicationRecord
  belongs_to :project
  belongs_to :user

  enum :role, { creator: "creator", editor: "editor", viewer: "viewer" }, default: "editor"

  validates :user_id, uniqueness: { scope: :project_id }
  validate :user_is_workspace_member, on: :create

  scope :pinned, -> { where(pinned: true) }

  after_commit :broadcast_changes, on: [:create, :update, :destroy]

  private

  def broadcast_changes
    broadcast_refresh_to project
  rescue => e
    Rails.logger.warn("Broadcast failed: #{e.message}")
  end

  def user_is_workspace_member
    return unless project&.workspace
    unless project.workspace.memberships.kept.exists?(user: user)
      errors.add(:user, :not_workspace_member, message: "must be a workspace member")
    end
  end
end
