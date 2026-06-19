module Onboarding
  class ProjectsController < BaseController
    before_action :require_workspace

    def new
      authorize Project
      @project = Current.workspace.projects.build
    end

    def create
      authorize Project
      @project = Current.workspace.projects.build(project_params)
      @project.created_by = Current.user

      if @project.save
        @project.project_memberships.create!(user: Current.user, role: "creator")
        redirect_to new_onboarding_team_path, notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def require_workspace
      redirect_to new_onboarding_workspace_path if Current.workspace.nil?
    end

    def project_params
      params.require(:project).permit(:name, :description)
    end
  end
end
