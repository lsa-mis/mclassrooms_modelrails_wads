class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create lookup]
  skip_onboarding_requirement only: :destroy
  require_unauthenticated_access only: :new
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
    @email_lookup_form = EmailLookupForm.new(email_address: params[:email_address])

    unless @email_lookup_form.valid?
      render :email_error
      return
    end

    email = @email_lookup_form.email_address.downcase.strip
    user = User.find_by(email_address: email)

    if user&.has_password?
      @email_address = email
      render :password_form
    elsif user
      token = MagicLinkToken.create_for_email(user.email_address)
      MagicLinkMailer.sign_in_link(user.email_address, token).deliver_later
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
