class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  require_unauthenticated_access only: :new
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_registration_path, alert: t("registrations.create.rate_limited") }

  def new
    if signups_open?
      @user = User.new
    else
      render :closed
    end
  end

  def create
    unless signups_open?
      render :closed, status: :unprocessable_entity
      return
    end

    @user = User.new(registration_params)
    authentication = nil

    ApplicationRecord.transaction do
      @user.save!
      authentication = @user.authentications.create!(
        provider: "email",
        uid: @user.email_address,
        # Park both pending claims (invitation + open-link join) — neither is
        # consumed until the user proves email ownership via the verification
        # link (Settings::ConnectedAccountsController#verify). Mirrors the
        # unverified-OAuth signup path.
        pending_invitation_token: session[:pending_invitation_token],
        pending_join_link_token: session[:pending_join_token]
      )
    end

    session.delete(:pending_invitation_token)
    session.delete(:pending_join_token)
    AuthenticationMailer.verification_email(authentication).deliver_later
    start_new_session_for(@user)
    redirect_to after_authentication_url, notice: t(".success")
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  private

  def registration_params
    params.require(:user).permit(
      :email_address, :first_name, :last_name,
      :password, :password_confirmation
    )
  end
end
