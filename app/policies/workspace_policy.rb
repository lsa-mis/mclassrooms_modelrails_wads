class WorkspacePolicy < ApplicationPolicy
  def index?
    true  # Any authenticated user can list their workspaces
  end

  def create?
    true  # Any authenticated user can create a workspace
  end

  def new?
    create?
  end

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
