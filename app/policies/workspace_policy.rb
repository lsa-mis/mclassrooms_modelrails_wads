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
    # Fork divergence (MiClassrooms, 2026-07-17): under the SHARED (directory)
    # posture the workspace is an internal admin construct, not a user-facing
    # page — so only directory admins (RoleResolver: owner/admin slugs) may view
    # the dashboard; non-admin members (viewers/editors) never see
    # /workspaces/:slug. Every OTHER posture keeps the template's member-visible
    # dashboard. Gating on the posture (reusing TenancyConfig.shared?, not a new
    # config flag) ties the rule to its reason and leaves multi-tenant forks
    # untouched. NOTE the coupling:
    # ApplicationController#not_authorized_redirect_path lands denied users on
    # workspace_path only when show? permits, so locking it here can't loop a
    # denied non-admin back onto a dashboard they can't see. can?("manage_workspace")
    # would be the WRONG admin notion — that permission is owner-only, so it
    # would lock out the `admin`-slug directory admins this fork grants.
    return membership.present? unless TenancyConfig.shared?

    RoleResolver.for(user).admin?
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
