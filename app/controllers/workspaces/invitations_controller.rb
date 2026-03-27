module Workspaces
  class InvitationsController < ApplicationController
    include WorkspaceScoped

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

      if params[:invitation][:magic_link] == "1"
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
      InvitationMailer.invite(invitation).deliver_later
      redirect_to workspace_invitations_path(@workspace), notice: t(".resent")
    end

    private

    def create_email_invitations
      emails = params[:invitation][:emails].to_s.split(/[\n,]/).map(&:strip).reject(&:blank?)
      role = @workspace.effective_roles.find(params[:invitation][:role_id])
      sent = 0
      skipped = 0

      emails.each do |email|
        normalized = email.downcase

        if @workspace.memberships.kept.joins(:user).where(users: { email_address: normalized }).exists?
          skipped += 1
          next
        end

        if @workspace.invitations.pending.where(email: normalized).exists?
          skipped += 1
          next
        end

        invitation = @workspace.invitations.create!(
          email: normalized,
          role: role,
          invited_by: Current.user,
          expires_at: 7.days.from_now
        )
        InvitationMailer.invite(invitation).deliver_later
        sent += 1
      end

      redirect_to workspace_invitations_path(@workspace),
        notice: t(".sent", sent: sent, skipped: skipped)
    end

    def create_magic_link
      role = @workspace.effective_roles.find(params[:invitation][:role_id])
      invitation = @workspace.invitations.create!(
        role: role,
        invited_by: Current.user,
        expires_at: 7.days.from_now
      )

      redirect_to workspace_invitations_path(@workspace),
        notice: t(".magic_link_created"),
        flash: { magic_link_url: accept_invitation_url(token: invitation.token) }
    end
  end
end
