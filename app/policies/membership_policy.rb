class MembershipPolicy < ApplicationPolicy
  def index?
    membership.present?
  end

  def update?
    can?("manage_members") && may_grant?(record.role)
  end

  def destroy?
    return false if record.workspace.discarded?

    if record.user == user
      # Self-leave case: user deactivating their own membership.
      return false if record.workspace.id == user.personal_workspace_id
      return false if record.role.slug == "owner" && record.workspace.owners.size == 1
      true
    else
      # Admin-deactivates-someone-else case (the rule prior to Path AA).
      can?("manage_members")
    end
  end

  def reactivate?
    can?("manage_members") && may_grant?(record.role)
  end

  def transfer_ownership?
    can?("manage_workspace")
  end
end
