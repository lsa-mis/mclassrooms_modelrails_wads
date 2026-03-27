class Membership < ApplicationRecord
  include Discardable
  include Trackable

  belongs_to :user
  belongs_to :workspace
  belongs_to :role

  validates :user_id, uniqueness: { scope: :workspace_id }
  validate :workspace_has_member_capacity, on: :create

  after_commit :broadcast_changes, on: [:create, :update]

  def change_role!(new_role)
    update!(role: new_role)
  end

  def deactivate!
    transaction do
      workspace.lock!
      validate_not_last_owner!
      discard!
      ProjectMembership.joins(:project)
        .where(projects: { workspace_id: workspace_id }, user_id: user_id)
        .destroy_all
    end
  end

  def reactivate!
    undiscard!
  end

  def transfer_ownership_to!(target_membership)
    owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
    admin_role = Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" }

    transaction do
      target_membership.update!(role: owner_role)
      update!(role: admin_role)
    end
  end

  private

  def broadcast_changes
    broadcast_refresh_to workspace
  rescue => e
    Rails.logger.warn("Broadcast failed: #{e.message}")
  end

  def workspace_has_member_capacity
    return unless workspace
    workspace.lock!
    if workspace.memberships.kept.count >= workspace.max_members
      errors.add(:base, :workspace_member_limit, message: "workspace has reached its member limit")
    end
  end

  def validate_not_last_owner!
    if role.slug == "owner" && workspace.memberships.kept.joins(:role).where(roles: { slug: "owner" }).count <= 1
      errors.add(:base, :last_owner)
      raise ActiveRecord::RecordInvalid, self
    end
  end
end
