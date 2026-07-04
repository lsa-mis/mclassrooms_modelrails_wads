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

  def archive?
    lifecycle_manageable?
  end

  def unarchive?
    lifecycle_manageable?
  end

  def destroy?
    lifecycle_manageable?
  end

  private

  # archive?/unarchive?/destroy? share one predicate so the three can't
  # silently drift (same pattern as ApplicationPolicy's new? -> create?).
  def lifecycle_manageable?
    can?("manage_workspace") && !record.home?
  end
end
