module Onboarding
  # Singular `resource :team` maps to a PLURAL controller name.
  class TeamsController < BaseController
    before_action :require_workspace_with_project

    def new
      authorize Invitation
      @invitation = Invitation.new
      @roles = Current.workspace.effective_roles
    end

    def create
      authorize Invitation

      emails = invitation_params[:emails].to_s.split(/[\n,]/).map(&:strip).reject(&:blank?)

      if emails.empty?
        flash.now[:alert] = t(".no_emails")
        @invitation = Invitation.new
        @roles = Current.workspace.effective_roles
        render :new, status: :unprocessable_entity
        return
      end

      role = Current.workspace.effective_roles.find(invitation_params[:role_id])
      Invitation.bulk_invite!(workspace: Current.workspace, emails: emails, role: role, invited_by: Current.user)

      Current.user.update!(onboarded_at: Time.current) unless Current.user.onboarded?
      redirect_to project_home_path, notice: t(".sent")
    end

    private

    def require_workspace_with_project
      redirect_to onboarding_path if Current.workspace.nil? || Current.workspace.projects.kept.none?
    end

    def project_home_path
      workspace_project_path(Current.workspace, Current.workspace.projects.kept.first)
    end

    def invitation_params
      params.require(:invitation).permit(:emails, :role_id)
    end
  end
end
