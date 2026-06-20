module Workspaces
  module Projects
    class ClientsidesController < ApplicationController
      include WorkspaceScoped
      before_action :set_project

      def edit
        authorize @project, :update?
      end

      def update
        authorize @project, :update?

        if @project.update(clientside_params)
          redirect_to edit_workspace_project_clientside_path(@workspace, @project),
            notice: t("clientside.settings.saved")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_project
        @project = @workspace.projects.kept.find_by!(slug: params[:project_slug])
        Current.project = @project
      end

      def clientside_params
        params.require(:project).permit(:clientside_enabled)
      end
    end
  end
end
