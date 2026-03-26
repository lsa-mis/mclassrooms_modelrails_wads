module Workspaces
  module Projects
    class InvitationsController < ApplicationController
      include WorkspaceScoped
      before_action :set_project

      def new
        authorize @project, :update?
        @invitation = Invitation.new
      end

      def create
        authorize @project, :update?
        viewer_role = Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" }

        @invitation = @project.invitations.build(
          email: invitation_params[:email]&.downcase,
          role: viewer_role,
          project_role: invitation_params[:project_role] || "editor",
          invited_by: Current.user,
          expires_at: 7.days.from_now
        )

        if @invitation.save
          InvitationMailer.invite(@invitation).deliver_later
          redirect_to workspace_project_memberships_path(@workspace, @project), notice: t(".success")
        else
          render :new, status: :unprocessable_entity
        end
      end

      private

      def set_project
        @project = @workspace.projects.kept.find_by!(slug: params[:project_slug])
      end

      def invitation_params
        params.require(:invitation).permit(:email, :project_role)
      end
    end
  end
end
