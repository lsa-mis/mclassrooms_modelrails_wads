class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create lookup]
  rate_limit to: 10, within: 3.minutes, only: [ :create, :lookup ], with: -> { redirect_to new_session_path, alert: t("sessions.create.rate_limited") }

  def new
  end

  def create
    user = User.find_by(email_address: params[:email_address])

    if user&.locked?
      redirect_to new_session_path, alert: t(".locked")
      return
    end

    if user&.authenticate(params[:password])
      user.register_successful_login!
      start_new_session_for(user)
      redirect_to after_authentication_url, notice: t(".success")
    else
      user&.register_failed_login!
      redirect_to new_session_path, alert: t(".failure")
    end
  end

  def lookup
    email = params[:email_address]&.downcase&.strip

    unless email&.match?(User::EMAIL_FORMAT)
      redirect_to new_session_path, alert: t(".invalid_email")
      return
    end

    user = User.find_by(email_address: email)

    if user&.has_password?
      @email_address = email
      render :password_form
    elsif user
      user.generate_magic_link_token!
      MagicLinkMailer.sign_in_link(user).deliver_later
      @email_address = email
      render :check_email
    else
      token = MagicLinkToken.create_for_email(email)
      MagicLinkMailer.registration_link(email, token).deliver_later
      @email_address = email
      render :check_email
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other, notice: t(".success")
  end
end
