module Workspaces
  class InvitationsController < ApplicationController
    include InvitationSending
    include WorkspaceScoped

    def new
      authorize Invitation
      @invitation = Invitation.new
      @roles = assignable_roles_for(Invitation)
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
      redirect_to workspace_members_path(@workspace), notice: t(".revoked")
    end

    private

    def create_email_invitations
      role = @workspace.effective_roles.find(invitation_params[:role_id])
      authorize_role_grant!(Invitation, role)

      result = Invitation.bulk_invite!(
        workspace: @workspace,
        emails: invitation_params[:emails],
        role: role,
        invited_by: Current.user
      )

      notice = t("workspaces.invitations.create.sent", sent: result[:sent], skipped: result[:skipped])
      # The cap is never applied silently: a sender who pasted more addresses
      # than we will take is told which ones went (D13).
      if result[:over_limit]
        notice += " " + t("workspaces.invitations.create.capped",
                          cap: Invitation::MAX_EMAILS_PER_SUBMISSION)
      end

      redirect_to workspace_members_path(@workspace), notice: notice
    end

    def create_magic_link
      role = @workspace.effective_roles.find(invitation_params[:role_id])
      authorize_role_grant!(Invitation, role)
      invitation = @workspace.invitations.create!(
        role: role,
        invited_by: Current.user,
        expires_at: 7.days.from_now
      )

      redirect_to workspace_members_path(@workspace),
        notice: t("workspaces.invitations.create.magic_link_created"),
        flash: { magic_link_url: accept_invitation_url(token: invitation.token) }
    end

    def invitation_params
      params.require(:invitation).permit(:emails, :role_id, :magic_link)
    end
  end
end
