class OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access

  def create
    auth_hash = request.env["omniauth.auth"]
    authentication = Authentication.find_by(provider: auth_hash.provider, uid: auth_hash.uid)
    resume_session

    if authentication
      # Existing OAuth link — update tokens and sign in
      authentication.update!(oauth_attrs(auth_hash))
      start_new_session_for(authentication.user)
      redirect_to root_path, notice: t("sessions.create.success")
    elsif Current.user
      # Signed-in user linking a new provider
      Current.user.authentications.create!(
        provider: auth_hash.provider,
        uid: auth_hash.uid,
        verified_at: Time.current,
        **oauth_attrs(auth_hash)
      )
      redirect_to account_connected_accounts_path, notice: t(".linked", provider: auth_hash.provider.titleize)
    else
      # New OAuth — find or create user
      user = find_verified_user_by_email(auth_hash.info.email) || create_user_from_oauth(auth_hash)
      user.authentications.create!(
        provider: auth_hash.provider,
        uid: auth_hash.uid,
        verified_at: Time.current,
        **oauth_attrs(auth_hash)
      )
      start_new_session_for(user)
      redirect_to root_path, notice: t("sessions.create.success")
    end
  end

  def failure
    redirect_to new_session_path, alert: t("sessions.create.oauth_failure")
  end

  private

  def oauth_attrs(auth_hash)
    {
      oauth_token: auth_hash.credentials.token,
      oauth_refresh_token: auth_hash.credentials.refresh_token,
      oauth_expires_at: auth_hash.credentials.expires_at ? Time.at(auth_hash.credentials.expires_at) : nil
    }
  end

  def find_verified_user_by_email(email)
    user = User.find_by(email_address: email)
    return nil unless user
    return user if user.authentications.email.where.not(verified_at: nil).exists?
    nil # Don't link to unverified accounts
  end

  def create_user_from_oauth(auth_hash)
    User.create!(
      email_address: auth_hash.info.email,
      first_name: auth_hash.info.first_name || auth_hash.info.name&.split&.first || "User",
      last_name: auth_hash.info.last_name || auth_hash.info.name&.split&.last || "",
      password: SecureRandom.urlsafe_base64(32)
    )
  end
end
