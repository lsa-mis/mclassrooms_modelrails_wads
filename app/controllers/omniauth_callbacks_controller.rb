class OmniauthCallbacksController < ApplicationController
  include Signupable

  # Fork deviation (MiClassrooms Phase 0 Task 7): providers whose NEW-USER
  # auto-provisioning bypasses SignupPolicy / SIGNUP_MODE. ONLY providers with
  # their own institutional access gate belong here, and the bypass only
  # applies while that gate is actually armed:
  #   - google: restricted by the ALLOWED_GOOGLE_DOMAINS allowlist
  #     (#google_domain_allowed?, enforced in #create before any branch runs)
  #     — but the allowlist being EMPTY means the gate is unarmed (disabled,
  #     the dev-friendly default), so an empty allowlist does NOT grant
  #     google a signup bypass either: #sso_signup_bypass? requires
  #     AuthConfig.allowed_google_domains.any? before treating google as
  #     gated, and google new-user signups fall back through the normal
  #     signups_open? check exactly like any non-bypass provider. This is the
  #     fail-open bug this comment used to invert — an unarmed allowlist is
  #     not an institutional gate.
  #   - okta: only accounts in the deployment's Okta org can complete the
  #     OIDC flow at all — org membership is intrinsic to the provider, so
  #     okta's bypass is unconditional (there's no "unarmed" state to check)
  # Everything else — github, and any provider a fork adds — stays behind
  # the signups_open? gate (fail-closed by default): its callback route is
  # live with allow_unauthenticated_access even when its button is hidden
  # under sso_only, so an ungated bypass would reopen public self-signup
  # through that provider while the instance is invite-only.
  # Values are normalized provider names (OmniauthAdapters.normalize_provider).
  SSO_SIGNUP_BYPASS_PROVIDERS = %w[google okta].freeze

  allow_unauthenticated_access

  def create
    identity = OauthIdentity.new(request.env["omniauth.auth"])
    resume_session

    # Fork deviation (MiClassrooms Phase 0 Task 7): Google domain allowlist,
    # checked first, for every Google callback (new user, returning user, and
    # signed-in-user linking alike) — not just at signup — so a Google
    # account outside the allowed domains never reaches any branch below.
    # Okta is NOT subject to this: org membership is Okta's own gate (see
    # config/initializers/omniauth.rb). Nothing is created or looked up
    # before this check runs.
    if identity.provider == "google" && !google_domain_allowed?(identity)
      redirect_to new_session_path,
        alert: t("omniauth_callbacks.create.google_domain_not_allowed"),
        status: :see_other
      return
    end

    existing = Authentication.find_by(provider: identity.provider, uid: identity.uid)

    if existing
      handle_existing_auth(existing, identity)
    elsif Current.user
      handle_signed_in_link(Current.user, identity)
    else
      handle_new_user_oauth(identity)
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

  def handle_existing_auth(auth, identity)
    if Current.user.present? && Current.user.id != auth.user_id
      # Cross-user collision: the OAuth provider+uid is already linked to a
      # different user. Notify the legitimate owner (defense-in-depth) so
      # they're aware someone tried to attach their identity elsewhere.
      # Throttled to prevent flooding a victim if many attackers attempt this.
      if EmailRecipientThrottle.allow!(auth.user.email_address, kind: :collision_alert)
        AuthenticationMailer.collision_alert(auth.user, identity.provider_name).deliver_later
      end
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.collision_other_user", provider: identity.provider_name)
    elsif auth.pending?
      if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
        AuthenticationMailer.link_verification_email(auth).deliver_later
      end
      redirect_to fallback_path,
        notice: t("omniauth_callbacks.create.pending_resent", email: auth.email)
    else
      auth.update!(identity.auth_attrs)
      stash_okta_logout_state(identity)
      start_new_session_for(auth.user)
      redirect_to after_authentication_url, notice: t("sessions.create.success")
    end
  end

  def handle_signed_in_link(user, identity)
    existing = user.authentications.find_by(provider: identity.provider)

    if existing&.verified?
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.already_linked", provider: identity.provider_name)
      return
    elsif existing&.pending?
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.pending_in_progress",
                 provider: identity.provider_name, email: existing.email)
      return
    end

    if identity.email.blank?
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.linking_failed")
      return
    end

    auth = user.authentications.build(
      provider: identity.provider,
      uid: identity.uid,
      email: identity.email,
      **identity.auth_attrs
    )

    if EmailNormalizer.equivalent?(identity.email, user.email_address) && identity.email_verified?
      auth.verified_at = Time.current
      auth.save!
      redirect_to settings_connected_accounts_path,
        notice: t("omniauth_callbacks.create.linked", provider: identity.provider_name)
    else
      auth.save!
      if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
        AuthenticationMailer.link_verification_email(auth).deliver_later
      end
      flash[:confirming_email_for] = auth.id
      redirect_to settings_connected_accounts_path,
        notice: t("omniauth_callbacks.create.pending", email: identity.email, provider: identity.provider_name)
    end
  end

  # Fork deviation (MiClassrooms Phase 0 Task 7): SSO-only posture — new-user
  # provisioning via the providers in SSO_SIGNUP_BYPASS_PROVIDERS (google +
  # okta — see the constant's comment for WHY only those two, and for the
  # google allowlist-armed condition #sso_signup_bypass? enforces) bypasses
  # SignupPolicy/SIGNUP_MODE. Their institutional gates (Google domain
  # allowlist, Okta org membership — both enforced before this method runs)
  # are this fork's access-control for SSO; SIGNUP_MODE remains the gate for
  # email self-signup (RegistrationsController,
  # MagicLinkCallbacksController#create), for any OAuth provider outside the
  # bypass list (GitHub today), and — critically — for google itself when its
  # allowlist is empty (unarmed), which behave exactly as before Task 7.
  #
  # The bypass exists because of an empirical finding: Task 6's Okta spec
  # appeared to provision new users successfully under
  # SIGNUP_MODE=invite_only, but that passed only because the spec's
  # top-level `before` stubbed Rails.configuration.x.signup.mode to :open —
  # under the real default, the signups_open? guard blocked new-user OAuth
  # signups exactly like email signup. See
  # spec/requests/omniauth_google_domains_spec.rb's "SSO provisioning
  # bypasses closed email self-signup" describe block, which pins both the
  # bypass (google/okta) and the non-bypass (github, and google with an empty
  # allowlist) against the unstubbed default.
  def handle_new_user_oauth(identity)
    unless sso_signup_bypass?(identity) || signups_open?
      redirect_to new_session_path,
                  alert: t("registrations.closed.oauth_blocked"),
                  status: :see_other
      return
    end

    if identity.email_verified?
      handle_verified_email_oauth(identity)
    else
      handle_unverified_email_oauth(identity)
    end
  end

  # Whether this provider's institutional gate is actually armed and may
  # therefore bypass SIGNUP_MODE for a brand-new user (see
  # SSO_SIGNUP_BYPASS_PROVIDERS above). Okta's gate (org membership) is
  # intrinsic to completing the OIDC flow at all, so it's unconditional.
  # Google's gate is the ALLOWED_GOOGLE_DOMAINS allowlist, which is OPT-IN —
  # an empty allowlist means the domain check is disabled (every domain
  # passes, the dev-friendly default), which is not an institutional gate at
  # all. Treating an unarmed allowlist as a bypass would fail OPEN: any
  # Google account could self-provision on an otherwise invite_only/SSO-only
  # instance. So google only gets the bypass when the allowlist is non-empty;
  # with an empty allowlist, google new-user signups fall back through the
  # same signups_open? check as every other non-bypass provider.
  def sso_signup_bypass?(identity)
    return false unless SSO_SIGNUP_BYPASS_PROVIDERS.include?(identity.provider)
    return true unless identity.provider == "google"

    AuthConfig.allowed_google_domains.any?
  end

  def handle_verified_email_oauth(identity)
    existing = find_verified_user_by_email(identity.email)
    @user = existing || create_user_from_oauth(identity)

    # A pre-existing user linking a new verified provider must not be silently
    # force-joined by a pending join token riding the session (drive-by join).
    success = commit_signup_atomically(@user, newly_registered: existing.nil?) do |user|
      user.authentications.create!(
        provider: identity.provider,
        uid: identity.uid,
        email: identity.email,
        verified_at: Time.current,
        **identity.auth_attrs
      )
    end

    if success
      stash_okta_logout_state(identity)
      start_new_session_for(@user)
      redirect_to after_authentication_url, notice: t("sessions.create.success")
    else
      redirect_to new_session_path, alert: t("omniauth_callbacks.create.linking_failed")
    end
  end

  def handle_unverified_email_oauth(identity)
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
      user = create_user_from_oauth(identity)
      auth = user.authentications.build(
        provider: identity.provider,
        uid: identity.uid,
        email: identity.email,
        # Park both pending claims for the deferred-OAuth flow (mirror
        # registrations_controller).
        pending_invitation_token: session[:pending_invitation_token],
        pending_join_link_digest: parked_join_digest,
        **identity.auth_attrs
      )
      auth.save!
    end

    # Tokens are safely persisted on the Authentication; clear from session.
    session.delete(:pending_invitation_token)
    session.delete(:pending_join_token)

    # RP-initiated logout (D4): stash now, at callback time — this path's
    # deferred sign-in happens later in
    # Settings::ConnectedAccountsController#verify, which has no auth_hash to
    # stash from. The OIDC flow DID complete in this browser (Okta has a live
    # IdP session here), so the eventual sign-out should still end it.
    # Verifying in the same browser inherits this session stash; verifying in
    # a different browser legitimately lacks it (no OIDC flow ever ran there),
    # so that first session skips RP logout — acceptable.
    stash_okta_logout_state(identity)

    # deliver_later runs after the transaction commits (project convention:
    # deliver_later inside a transaction can enqueue a job that fires on rollback).
    if EmailRecipientThrottle.allow!(auth.email, kind: :verification)
      AuthenticationMailer.link_verification_email(auth).deliver_later
    end
    redirect_to new_session_path,
      notice: t("omniauth_callbacks.create.unverified_email_pending", email: identity.email)
  end

  def fallback_path
    Current.user.present? ? settings_connected_accounts_path : new_session_path
  end

  # Fork deviation (MiClassrooms Phase 0 Task 7): Google domain allowlist —
  # case-insensitive EXACT match against the domain part of the OAuth-supplied
  # email — never end_with?/include? substring matching, which would let
  # "evilumich.edu" or "umich.edu.evil.com" slip past a naive check. The
  # email is canonicalized
  # through EmailNormalizer.normalize (NFC + strip + downcase + punycoded
  # domain — the same normalizer this controller already uses for email
  # equality) and AuthConfig.allowed_google_domains applies the identical
  # canonicalization to each allowlist entry at read time, so both sides of
  # the include? compare in the same form. An empty allowlist
  # (ALLOWED_GOOGLE_DOMAINS unset) disables the check entirely.
  def google_domain_allowed?(identity)
    allowlist = AuthConfig.allowed_google_domains
    return true if allowlist.empty?

    email = EmailNormalizer.normalize(identity.email)
    return false if email.blank?

    local, _, domain = email.rpartition("@")
    return false if local.blank? || domain.blank?

    allowlist.include?(domain)
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
  def stash_okta_logout_state(identity)
    return unless identity.provider == "okta"

    session[:okta_id_token] = identity.id_token if identity.id_token.present?
  end

  # The join token is hashed at rest (WorkspaceJoinLink stores only a digest),
  # so park the digest — not the plaintext — for the deferred-OAuth claim.
  def parked_join_digest
    token = session[:pending_join_token]
    WorkspaceJoinLink.digest(token) if token.present?
  end

  def find_verified_user_by_email(email)
    user = User.find_by(email_address: email)
    return nil unless user
    return user if user.authentications.email.where.not(verified_at: nil).exists?
    nil
  end

  def create_user_from_oauth(identity)
    User.create!(
      email_address: identity.email,
      first_name: identity.first_name,
      last_name: identity.last_name
    )
  end
end
