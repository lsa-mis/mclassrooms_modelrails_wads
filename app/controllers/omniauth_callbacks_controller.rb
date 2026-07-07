class OmniauthCallbacksController < ApplicationController
  include Signupable

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
      # Cross-user collision: the OAuth provider+uid is already linked to a
      # different user. Notify the legitimate owner (defense-in-depth) so
      # they're aware someone tried to attach their identity elsewhere.
      # Throttled to prevent flooding a victim if many attackers attempt this.
      provider_name = Authentication.display_name_for(normalized_provider(auth_hash))
      if EmailRecipientThrottle.allow!(auth.user.email_address, kind: :collision_alert)
        AuthenticationMailer.collision_alert(auth.user, provider_name).deliver_later
      end
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.collision_other_user", provider: provider_name)
    elsif auth.pending?
      if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
        AuthenticationMailer.link_verification_email(auth).deliver_later
      end
      redirect_to fallback_path,
        notice: t("omniauth_callbacks.create.pending_resent", email: auth.email)
    else
      auth.update!(oauth_attrs(auth_hash))
      stash_okta_logout_state(auth_hash)
      start_new_session_for(auth.user)
      redirect_to after_authentication_url, notice: t("sessions.create.success")
    end
  end

  def handle_signed_in_link(user, auth_hash)
    existing = user.authentications.find_by(provider: normalized_provider(auth_hash))

    if existing&.verified?
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.already_linked",
                 provider: Authentication.display_name_for(normalized_provider(auth_hash)))
      return
    elsif existing&.pending?
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.pending_in_progress",
                 provider: Authentication.display_name_for(normalized_provider(auth_hash)),
                 email: existing.email)
      return
    end

    oauth_email = auth_hash.info.email
    if oauth_email.blank?
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.linking_failed")
      return
    end

    email_matches = EmailNormalizer.equivalent?(oauth_email, user.email_address)

    auth = user.authentications.build(
      provider: normalized_provider(auth_hash),
      uid: auth_hash.uid,
      email: oauth_email,
      **oauth_attrs(auth_hash)
    )

    if email_matches && oauth_email_verified?(auth_hash)
      auth.verified_at = Time.current
      auth.save!
      redirect_to settings_connected_accounts_path,
        notice: t("omniauth_callbacks.create.linked", provider: Authentication.display_name_for(normalized_provider(auth_hash)))
    else
      auth.save!
      if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
        AuthenticationMailer.link_verification_email(auth).deliver_later
      end
      flash[:confirming_email_for] = auth.id
      redirect_to settings_connected_accounts_path,
        notice: t("omniauth_callbacks.create.pending",
                  email: oauth_email, provider: Authentication.display_name_for(normalized_provider(auth_hash)))
    end
  end

  def handle_new_user_oauth(auth_hash)
    unless signups_open?
      redirect_to new_session_path,
                  alert: t("registrations.closed.oauth_blocked"),
                  status: :see_other
      return
    end

    if oauth_email_verified?(auth_hash)
      handle_verified_email_oauth(auth_hash)
    else
      handle_unverified_email_oauth(auth_hash)
    end
  end

  def handle_verified_email_oauth(auth_hash)
    @user = find_verified_user_by_email(auth_hash.info.email) || create_user_from_oauth(auth_hash)

    success = commit_signup_atomically(@user) do |user|
      user.authentications.create!(
        provider: normalized_provider(auth_hash),
        uid: auth_hash.uid,
        email: auth_hash.info.email,
        verified_at: Time.current,
        **oauth_attrs(auth_hash)
      )
    end

    if success
      stash_okta_logout_state(auth_hash)
      start_new_session_for(@user)
      redirect_to after_authentication_url, notice: t("sessions.create.success")
    else
      redirect_to new_session_path, alert: t("omniauth_callbacks.create.linking_failed")
    end
  end

  def handle_unverified_email_oauth(auth_hash)
    # OAuth provider explicitly reports email as unverified (e.g., Google's
    # info.email_verified: false). Refuse to auto-link to an existing user
    # (account-takeover risk) and refuse to auto-verify. Create the user
    # fresh — if the email already belongs to another account, User
    # validation/uniqueness raises and the outer rescue surfaces a generic
    # "linking failed" alert. Otherwise, create the auth as pending and
    # email a verification link without signing the user in.
    #
    # NOTE: does NOT call commit_signup_atomically — that concern calls
    # accept_pending_invitation! which would consume the invitation immediately.
    # Instead, we persist the invitation token on the pending Authentication so
    # it can be claimed when the user proves email ownership by clicking the
    # verification link (Settings::ConnectedAccountsController#verify, Task 9).
    auth = nil
    ApplicationRecord.transaction do
      user = create_user_from_oauth(auth_hash)
      auth = user.authentications.build(
        provider: normalized_provider(auth_hash),
        uid: auth_hash.uid,
        email: auth_hash.info.email,
        # Park both pending claims for the deferred-OAuth flow (mirror
        # registrations_controller).
        pending_invitation_token: session[:pending_invitation_token],
        pending_join_link_token: session[:pending_join_token],
        **oauth_attrs(auth_hash)
      )
      auth.save!
    end

    # Tokens are safely persisted on the Authentication; clear from session.
    session.delete(:pending_invitation_token)
    session.delete(:pending_join_token)

    # deliver_later runs after the transaction commits (project convention:
    # deliver_later inside a transaction can enqueue a job that fires on rollback).
    if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
      AuthenticationMailer.link_verification_email(auth).deliver_later
    end
    redirect_to new_session_path,
      notice: t("omniauth_callbacks.create.unverified_email_pending", email: auth_hash.info.email)
  end

  def fallback_path
    Current.user.present? ? settings_connected_accounts_path : new_session_path
  end

  def normalized_provider(auth_hash)
    OmniauthAdapters.normalize_provider(auth_hash.provider)
  end

  # RP-initiated logout (Task 6, D4): stash the OIDC id_token for the
  # lifetime of the browser session so SessionsController#destroy can hand
  # it back to Okta as id_token_hint on sign-out. Never persisted to the
  # Authentication row — there's no column for it, and it's only meaningful
  # for the session that minted it.
  #
  # Gated on the normalized provider (not merely "id_token present") because
  # Google's strategy is also OIDC-based and populates credentials.id_token
  # too (omniauth-google-oauth2#credentials) — without this guard, signing in
  # via Google would incorrectly route sign-out through Okta's
  # end_session_endpoint. The mocked Google specs never set id_token, so that
  # bug would only have surfaced against real Google tokens in production.
  def stash_okta_logout_state(auth_hash)
    return unless normalized_provider(auth_hash) == "okta"

    id_token = auth_hash.credentials&.id_token
    session[:okta_id_token] = id_token if id_token.present?
  end

  # OAuth providers may explicitly mark the supplied email as unverified
  # (e.g., Google returns info.email_verified: false for unverified Google
  # accounts). When set to false we refuse to auto-verify the authentication
  # or auto-link to an existing user — both would enable account takeover via
  # an attacker-controlled unverified Google account. Providers that don't
  # expose this field (e.g., GitHub) are treated as implicitly verified,
  # preserving existing behavior. Only an explicit `false` triggers the gate.
  def oauth_email_verified?(auth_hash)
    auth_hash.info.email_verified != false
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
