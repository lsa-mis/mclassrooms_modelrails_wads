class WorkspacePolicy < ApplicationPolicy
  def show?
    membership.present?
  end

  def update?
    can?("manage_workspace")
  end

  def destroy?
    can?("manage_workspace")
  end
end
