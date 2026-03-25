class MembershipPolicy < ApplicationPolicy
  def index?
    membership.present?
  end

  def update?
    can?("manage_members")
  end

  def destroy?
    can?("manage_members") && record.user != user
  end

  def reactivate?
    can?("manage_members")
  end

  def transfer_ownership?
    can?("manage_workspace")
  end
end
