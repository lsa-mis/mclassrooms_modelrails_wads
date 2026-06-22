class InvitationAcceptsController < ApplicationController
  allow_unauthenticated_access

  def show
    @invitation = find_valid_invitation
    return unless @invitation

    # An unauthenticated invitee will Sign in / Register next; stash the
    # invitation so SignupPolicy opens the gate under :invite_only and
    # Signupable consumes it on signup (email-match guarded at consume).
    session[:pending_invitation_token] = @invitation.token unless authenticated?
  end

  def create
    @invitation = find_valid_invitation
    return unless @invitation

    if authenticated?
      begin
        # Route through consume! so the signed-in accept path inherits the same
        # email-match guard as signup/verification — an invitation addressed to
        # a specific email can't be claimed by a signed-in user with a different
        # one. (Emailless magic-link invitations stay bearer.)
        Invitation.consume!(token: @invitation.token, user: Current.user, expected_email: Current.user.email_address)
        if @invitation.client_invite?
          redirect_to clientside_project_path(@invitation.invitable), notice: t(".success")
        elsif @invitation.invitable_type == "Project"
          redirect_to workspace_project_path(@invitation.invitable.workspace, @invitation.invitable), notice: t(".success")
        else
          redirect_to workspace_path(@invitation.invitable), notice: t(".success")
        end
      rescue Invitation::EmailMismatch
        redirect_to root_path, alert: t(".email_mismatch")
      rescue Invitation::NotAcceptable, ActiveRecord::RecordInvalid
        redirect_to root_path, alert: t(".acceptance_failed")
      end
    else
      session[:pending_invitation_token] = @invitation.token
      redirect_to new_session_path, notice: t(".register_first")
    end
  end

  private

  def find_valid_invitation
    invitation = Invitation.find_by(token: params[:token])

    if invitation.nil?
      redirect_to root_path, alert: t(".invalid_token")
      return nil
    elsif !invitation.pending? || invitation.expired?
      redirect_to root_path, alert: t(".expired_or_used")
      return nil
    end

    invitation
  end
end
