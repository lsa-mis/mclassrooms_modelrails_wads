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
      # Last-owner guard: one indexed EXISTS, fired only for owner rows —
      # cheaper and fresher than materializing the full owner roster.
      return false if record.owner? && !Membership.other_kept_owners(record.workspace_id, excluding: record.id).exists?
      true
    else
      # Admin-deactivates-someone-else case.
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
