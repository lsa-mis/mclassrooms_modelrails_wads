module Clientside
  # External client area. Clients are Users but NOT workspace members, so this
  # area never uses WorkspaceScoped / Current.workspace. Projects are resolved
  # ONLY through the current user's kept ClientAccess (Clientside #1).
  class BaseController < ApplicationController
    # A client (external User, possibly onboarded_at: nil under :none) must reach
    # the client area rather than being funneled into the onboarding wizard.
    skip_onboarding_requirement
    layout "clientside"

    private

    def set_client_project
      slug = params[:project_id] || params[:id]
      # Resolve slug WITHIN the client's own projects — slugs are unique only
      # per workspace, so a global find_by can resolve the wrong project.
      project = Project.where(id: accessible_project_ids).find_by(slug: slug)
      if project.nil? || !project.client_accessible?
        redirect_to clientside_projects_path, alert: t("clientside.area.no_access")
        return
      end
      @project = project
      Current.project = @project
    end

    # The current client's reachable project ids — every kept ClientAccess they
    # hold. Both set_client_project (show) and ProjectsController#index scope to
    # this set; keeping it in one place stops the two from drifting.
    def accessible_project_ids
      Current.user.client_accesses.kept.select(:project_id)
    end

    def ensure_clientside_enabled
      return if @project&.clientside_enabled?
      redirect_to clientside_projects_path, alert: t("clientside.area.unavailable")
    end
  end
end
