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
      # Project#to_param returns slug; resolve by slug then verify client access.
      project = Project.find_by(slug: slug)
      access = project && Current.user.client_accesses.kept.find_by(project_id: project.id)
      if access.nil?
        redirect_to clientside_projects_path, alert: t("clientside.area.no_access")
        return
      end
      @project = access.project
      Current.project = @project
    end

    def ensure_clientside_enabled
      return if @project&.clientside_enabled?
      redirect_to clientside_projects_path, alert: t("clientside.area.unavailable")
    end
  end
end
