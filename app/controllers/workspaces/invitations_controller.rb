module Workspaces
  class InvitationsController < ApplicationController
    include WorkspaceScoped

    rate_limit to: 10, within: 3.minutes, only: :resend,
      by: -> { Current.user&.id || request.remote_ip },
      with: -> { redirect_to workspace_invitations_path(@workspace), alert: t("workspaces.invitations.resend.rate_limited") }

    def index
      authorize Invitation
      @invitations = @workspace.invitations.includes(:role).order(created_at: :desc)
    end

    def new
      authorize Invitation
      @invitation = Invitation.new
      @roles = @workspace.effective_roles
    end

    def create
      authorize Invitation

      if invitation_params[:magic_link] == "1"
        create_magic_link
      else
        create_email_invitations
      end
    end

    def destroy
      invitation = @workspace.invitations.find(params[:id])
      authorize invitation
      invitation.revoke!
      redirect_to workspace_invitations_path(@workspace), notice: t(".revoked")
    end

    def resend
      invitation = @workspace.invitations.find(params[:id])
      authorize invitation
      invitation.resend!
      if invitation.magic_link?
        redirect_to workspace_invitations_path(@workspace),
          notice: t(".magic_link_refreshed"),
          flash: { magic_link_url: accept_invitation_url(token: invitation.token) }
      else
        InvitationMailer.invite(invitation).deliver_later
        redirect_to workspace_invitations_path(@workspace), notice: t(".resent")
      end
    end

    private

    def create_email_invitations
      emails = invitation_params[:emails].to_s.split(/[\n,]/).map(&:strip).reject(&:blank?)
      role = @workspace.effective_roles.find(invitation_params[:role_id])

      result = Invitation.bulk_invite!(
        workspace: @workspace,
        emails: emails,
        role: role,
        invited_by: Current.user
      )

      redirect_to workspace_invitations_path(@workspace),
        notice: t(".sent", sent: result[:sent], skipped: result[:skipped])
    end

    def create_magic_link
      role = @workspace.effective_roles.find(invitation_params[:role_id])
      invitation = @workspace.invitations.create!(
        role: role,
        invited_by: Current.user,
        expires_at: 7.days.from_now
      )

      redirect_to workspace_invitations_path(@workspace),
        notice: t(".magic_link_created"),
        flash: { magic_link_url: accept_invitation_url(token: invitation.token) }
    end

    def invitation_params
      params.require(:invitation).permit(:emails, :role_id, :magic_link)
    end
  end
end
