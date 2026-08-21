class MembershipPolicy < ApplicationPolicy
  def index?
    membership.present?
  end

  def update?
    can?("manage_members") && may_grant?(record.role)
  end

  def destroy?
    return false if record.workspace.discarded?

    self_leave? ? may_leave? : can?("manage_members")
  end

  def reactivate?
    can?("manage_members") && may_grant?(record.role)
  end

  def transfer_ownership?
    can?("manage_workspace")
  end

  private

  def self_leave?
    record.user == user
  end

  def may_leave?
    !personal_workspace? && !sole_owner?
  end

  def personal_workspace?
    record.workspace.id == user.personal_workspace_id
  end

  # One indexed EXISTS, fired only for owner rows — cheaper and fresher than
  # materializing the full owner roster.
  def sole_owner?
    record.owner? && !Membership.other_kept_owners(record.workspace_id, excluding: record.id).exists?
  end
end
