class InvitationAcceptsController < ApplicationController
  allow_unauthenticated_access

  def show
    @invitation = find_valid_invitation
    return unless @invitation
  end

  def create
    @invitation = find_valid_invitation
    return unless @invitation

    if authenticated?
      @invitation.accept!(Current.user)
      redirect_to workspace_path(@invitation.invitable), notice: t(".success")
    else
      session[:pending_invitation_token] = @invitation.token
      redirect_to new_registration_path, notice: t(".register_first")
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
