class Membership < ApplicationRecord
  include Discardable

  belongs_to :user
  belongs_to :workspace
  belongs_to :role

  validates :user_id, uniqueness: { scope: :workspace_id }

  def change_role!(new_role)
    update!(role: new_role)
  end

  def deactivate!
    validate_not_last_owner!
    discard!
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

  def validate_not_last_owner!
    if role.slug == "owner" && workspace.memberships.kept.joins(:role).where(roles: { slug: "owner" }).count <= 1
      errors.add(:base, :last_owner)
      raise ActiveRecord::RecordInvalid, self
    end
  end
end
