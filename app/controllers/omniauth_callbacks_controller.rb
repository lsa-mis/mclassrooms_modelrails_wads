class OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access

  def create
    auth_hash = request.env["omniauth.auth"]
    resume_session
    existing = Authentication.find_by(provider: normalized_provider(auth_hash), uid: auth_hash.uid)

    if existing
      handle_existing_auth(existing, auth_hash)
    elsif Current.user
      handle_signed_in_link(Current.user, auth_hash)
    else
      handle_new_user_oauth(auth_hash)
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, ArgumentError
    redirect_to fallback_path,
      alert: t("omniauth_callbacks.create.linking_failed")
  end

  def failure
    redirect_to new_session_path,
      alert: t("sessions.create.oauth_failure")
  end

  private

  def handle_existing_auth(auth, auth_hash)
    if Current.user.present? && Current.user.id != auth.user_id
      redirect_to account_connected_accounts_path,
        alert: t("omniauth_callbacks.create.collision_other_user",
                 provider: Authentication.display_name_for(normalized_provider(auth_hash)))
    elsif auth.pending?
      auth.generate_verification_token!
      AuthenticationMailer.link_verification_email(auth).deliver_later
      redirect_to fallback_path,
        notice: t("omniauth_callbacks.create.pending_resent", email: auth.email)
    else
      auth.update!(oauth_attrs(auth_hash))
      start_new_session_for(auth.user)
      redirect_to root_path, notice: t("sessions.create.success")
    end
  end

  def handle_signed_in_link(user, auth_hash)
    existing = user.authentications.find_by(provider: normalized_provider(auth_hash))

    if existing&.verified?
      redirect_to account_connected_accounts_path,
        alert: t("omniauth_callbacks.create.already_linked",
                 provider: Authentication.display_name_for(normalized_provider(auth_hash)))
      return
    elsif existing&.pending?
      redirect_to account_connected_accounts_path,
        alert: t("omniauth_callbacks.create.pending_in_progress",
                 provider: Authentication.display_name_for(normalized_provider(auth_hash)),
                 email: existing.email)
      return
    end

    oauth_email = auth_hash.info.email
    if oauth_email.blank?
      redirect_to account_connected_accounts_path,
        alert: t("omniauth_callbacks.create.linking_failed")
      return
    end

    email_matches = oauth_email.strip.downcase == user.email_address.to_s.downcase

    auth = user.authentications.build(
      provider: normalized_provider(auth_hash),
      uid: auth_hash.uid,
      email: oauth_email,
      **oauth_attrs(auth_hash)
    )

    if email_matches
      auth.verified_at = Time.current
      auth.save!
      redirect_to account_connected_accounts_path,
        notice: t("omniauth_callbacks.create.linked", provider: Authentication.display_name_for(normalized_provider(auth_hash)))
    else
      auth.assign_verification_token
      auth.save!
      AuthenticationMailer.link_verification_email(auth).deliver_later
      flash[:confirming_email_for] = auth.id
      redirect_to account_connected_accounts_path,
        notice: t("omniauth_callbacks.create.pending",
                  email: oauth_email, provider: Authentication.display_name_for(normalized_provider(auth_hash)))
    end
  end

  def handle_new_user_oauth(auth_hash)
    user = find_verified_user_by_email(auth_hash.info.email) || create_user_from_oauth(auth_hash)
    user.authentications.create!(
      provider: normalized_provider(auth_hash),
      uid: auth_hash.uid,
      email: auth_hash.info.email,
      verified_at: Time.current,
      **oauth_attrs(auth_hash)
    )
    start_new_session_for(user)
    redirect_to root_path, notice: t("sessions.create.success")
  end

  def fallback_path
    Current.user.present? ? account_connected_accounts_path : new_session_path
  end

  def normalized_provider(auth_hash)
    OmniauthAdapters.normalize_provider(auth_hash.provider)
  end

  def oauth_attrs(auth_hash)
    attrs = {
      oauth_token: auth_hash.credentials.token,
      oauth_refresh_token: auth_hash.credentials.refresh_token,
      oauth_expires_at: auth_hash.credentials.expires_at ? Time.at(auth_hash.credentials.expires_at) : nil
    }
    attrs[:avatar_url] = auth_hash.info.image if auth_hash.info.image.present?
    attrs
  end

  def find_verified_user_by_email(email)
    user = User.find_by(email_address: email)
    return nil unless user
    return user if user.authentications.email.where.not(verified_at: nil).exists?
    nil
  end

  def create_user_from_oauth(auth_hash)
    User.create!(
      email_address: auth_hash.info.email,
      first_name: auth_hash.info.first_name.presence || auth_hash.info.name&.split&.first || "User",
      last_name: auth_hash.info.last_name.presence || auth_hash.info.name&.split&.last || "User"
    )
  end
end
