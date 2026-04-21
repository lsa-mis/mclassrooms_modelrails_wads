class ProjectMembership < ApplicationRecord
  include Broadcastable

  belongs_to :project
  belongs_to :user

  enum :role, { creator: "creator", editor: "editor", viewer: "viewer" }, default: "editor"

  validates :user_id, uniqueness: { scope: :project_id }
  validate :user_is_workspace_member, on: :create

  scope :pinned, -> { where(pinned: true) }

  def self.broadcast_events
    [ :create, :update, :destroy ]
  end

  private

  def broadcast_target
    project
  end

  def user_is_workspace_member
    return unless project&.workspace
    unless project.workspace.memberships.kept.exists?(user: user)
      errors.add(:user, :not_workspace_member)
    end
  end
end
