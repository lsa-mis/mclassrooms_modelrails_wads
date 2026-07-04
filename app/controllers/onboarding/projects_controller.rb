module Onboarding
  class ProjectsController < BaseController
    before_action :require_workspace

    def new
      authorize Project
      @project = Current.workspace.projects.build
    end

    def create
      authorize Project
      raise Suspendable::SuspendedError if Current.workspace.suspended?
      @project = Current.workspace.projects.build(project_params)
      @project.created_by = Current.user

      if @project.save
        @project.project_memberships.create!(user: Current.user, role: "creator")
        redirect_to onboarding_after_project_path, notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def require_workspace
      redirect_to new_onboarding_workspace_path if Current.workspace.nil?
    end

    # Forward-only: route through the tools step only when the registry offers a
    # real choice; otherwise straight to the team step.
    def onboarding_after_project_path
      if ProjectTools::Registry.toggleable.size > 1
        new_onboarding_tools_path
      else
        new_onboarding_team_path
      end
    end

    def project_params
      params.require(:project).permit(:name, :description)
    end
  end
end
