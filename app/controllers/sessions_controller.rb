class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create lookup password_form]
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

    if user
      token = MagicLinkToken.create_for_email(user.email_address)
      MagicLinkMailer.sign_in_link(user.email_address, token).deliver_later
      @email_address = email
      @has_password = user.has_password?
      render :check_email
    else
      unless signups_open?
        render :closed, status: :unprocessable_entity
        return
      end
      token = MagicLinkToken.create_for_email(email)
      MagicLinkMailer.registration_link(email, token).deliver_later
      @email_address = email
      render :check_email
    end
  end

  def password_form
    @email_address = params[:email_address]
  end

  def destroy
    okta_id_token = session.delete(:okta_id_token)
    terminate_session

    if okta_id_token.present?
      redirect_to okta_end_session_url(okta_id_token), allow_other_host: true, status: :see_other
    else
      redirect_to new_session_path, status: :see_other, notice: t(".success")
    end
  end

  private

  # RP-initiated logout (Task 6, D4): when the session being torn down
  # originated from an Okta sign-in (OmniauthCallbacksController stashed the
  # id_token — see #stash_okta_logout_state there), redirect through Okta's
  # end_session_endpoint instead of straight back to sign-in. This actually
  # ends the user's session at Okta too; otherwise "sign out" here would
  # leave them silently still signed in at the IdP, able to sign back in
  # without re-entering credentials. id_token_hint identifies which Okta
  # session to end; post_logout_redirect_uri must be a URI Okta allows for
  # this app (configured alongside the callback URL in the Okta admin
  # console). No id_token in session (password/magic-link/Google/GitHub
  # sign-in, or Okta not configured) falls through to the branch above,
  # unchanged.
  def okta_end_session_url(id_token)
    query = { id_token_hint: id_token, post_logout_redirect_uri: new_session_url }.to_query
    "#{ENV['OKTA_ISSUER'].to_s.chomp('/')}/v1/logout?#{query}"
  end
end
