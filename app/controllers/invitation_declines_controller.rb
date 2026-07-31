class InvitationDeclinesController < ApplicationController
  allow_unauthenticated_access

  def show
    @invitation = find_valid_invitation
  end

  def create
    @invitation = find_valid_invitation
    return unless @invitation

    @invitation.decline!
    redirect_to root_path, notice: t(".success")
  end

  private

  def find_valid_invitation
    invitation = Invitation.find_by(token: params[:token])

    # Absolute key: this filter serves both #show and #create.
    if invitation.nil? || !invitation.pending? || invitation.expired?
      redirect_to root_path, alert: t("invitation_declines.invalid")
      return nil
    end

    invitation
  end
end
