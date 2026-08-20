# Resolves the request's project for controllers nested under a workspace.
# Depends on WorkspaceScoped having set @workspace first — the tenant
# isolation invariant is that projects are only ever resolved THROUGH the
# request's workspace, never via a class-level finder (see docs/developer/extending).
#
# Assigning Current.project is part of the contract: ResourcePolicy and
# ProjectMembershipPolicy fall back on it for class-level `authorize` calls.
module ProjectScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_project
  end

  private

  def set_project
    slug = params[:project_slug] || params[:slug]
    @project = @workspace.projects.kept.find_by!(slug: slug)
    Current.project = @project
  rescue ActiveRecord::RecordNotFound
    redirect_to workspace_projects_path(@workspace), alert: t("workspaces.projects.not_found")
  end
end
