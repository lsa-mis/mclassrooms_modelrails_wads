class RegistrationsController < ApplicationController
  allow_unauthenticated_access

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
end
