module Workspaces
  module Projects
    class MembershipsController < ApplicationController
      include WorkspaceScoped
      before_action :set_project

      def index
        authorize ProjectMembership
        @memberships = @project.project_memberships.includes(:user)
      end

      def new
        authorize ProjectMembership
        @available_members = @workspace.memberships.kept.includes(:user)
          .where.not(user_id: @project.project_memberships.select(:user_id))
      end

      def create
        authorize ProjectMembership
        @pm = @project.project_memberships.build(membership_params)

        if @pm.save
          redirect_to workspace_project_memberships_path(@workspace, @project), notice: t(".success")
        else
          @available_members = @workspace.memberships.kept.includes(:user)
            .where.not(user_id: @project.project_memberships.select(:user_id))
          render :new, status: :unprocessable_entity
        end
      end

      def update
        @pm = @project.project_memberships.find(params[:id])
        authorize @pm
        @pm.update!(role: params[:project_membership][:role])
        redirect_to workspace_project_memberships_path(@workspace, @project), notice: t(".role_updated")
      end

      def destroy
        @pm = @project.project_memberships.find(params[:id])
        authorize @pm
        @pm.destroy!
        redirect_to workspace_project_memberships_path(@workspace, @project), notice: t(".removed")
      end

      def toggle_pin
        # Security: find by Current.user, not URL param, to prevent IDOR
        @pm = @project.project_memberships.find_by!(user: Current.user)
        authorize @pm
        @pm.update!(pinned: !@pm.pinned)
        redirect_back fallback_location: workspace_projects_path(@workspace), notice: t(".toggled")
      end

      private

      def set_project
        @project = @workspace.projects.kept.find_by!(slug: params[:project_slug])
        Current.project = @project
      end

      def membership_params
        params.require(:project_membership).permit(:user_id, :role)
      end
    end
  end
end
