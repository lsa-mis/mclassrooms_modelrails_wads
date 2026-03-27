class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_registration_path, alert: t("registrations.create.rate_limited") }

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    if @user.save
      authentication = @user.authentications.create!(
        provider: "email",
        uid: @user.email_address
      )
      authentication.generate_verification_token!
      AuthenticationMailer.verification_email(authentication).deliver_later
      start_new_session_for(@user)
      accept_pending_invitation(@user)
      redirect_to root_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(
      :email_address, :first_name, :last_name,
      :password, :password_confirmation
    )
  end

  def accept_pending_invitation(user)
    token = session.delete(:pending_invitation_token)
    return unless token

    invitation = Invitation.find_by(token: token)
    invitation&.accept!(user) if invitation&.pending? && !invitation&.expired?
  end
end
