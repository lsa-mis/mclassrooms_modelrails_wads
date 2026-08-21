class OmniauthCallbacksController < ApplicationController
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

  # OauthLink outcome → session key to drop once the outcome spent it.
  SESSION_TOKEN_KEYS = {
    invitation: :pending_invitation_token,
    join: :pending_join_token
  }.freeze

  # The linking decision tree lives in OauthLink (unit-tested there); this
  # action only adapts it to HTTP: session in, redirect + flash out.
  def create
    identity = OauthIdentity.new(request.env["omniauth.auth"])
    resume_session

    # Fork deviation (MiClassrooms Phase 0 Task 7): Google domain allowlist,
    # checked first, for every Google callback (new user, returning user, and
    # signed-in-user linking alike) — not just at signup — so a Google
    # account outside the allowed domains never reaches OauthLink at all.
    # Okta is NOT subject to this: org membership is Okta's own gate (see
    # config/initializers/omniauth.rb). Nothing is created or looked up
    # before this check runs.
    if identity.provider == "google" && !google_domain_allowed?(identity)
      redirect_to new_session_path,
        alert: t("omniauth_callbacks.create.google_domain_not_allowed"),
        status: :see_other
      return
    end

    # signups_open is the constructor's policy seam: the fork widens it with
    # the SSO bypass (see SSO_SIGNUP_BYPASS_PROVIDERS) so OauthLink itself
    # stays identical to the template's.
    outcome = OauthLink.new(
      request.env["omniauth.auth"],
      actor: Current.user,
      signups_open: sso_signup_bypass?(identity) || signups_open?,
      invitation_token: session[:pending_invitation_token],
      join_token: session[:pending_join_token]
    ).claim

    # RP-initiated logout (Task 6, D4): the OIDC flow completed in THIS
    # browser on these outcomes — a session minted now (:signed_in) or later
    # (:unverified_pending, deferred sign-in via the verification link) should
    # hand id_token_hint back to Okta on sign-out. Session write, so it lives
    # here, not in OauthLink.
    if %i[signed_in unverified_pending].include?(outcome.code)
      stash_okta_logout_state(identity)
    end

    outcome.spent_tokens.each { |kind| session.delete(SESSION_TOKEN_KEYS.fetch(kind)) }
    redirect_for(outcome)
  end

  def failure
    redirect_to new_session_path,
      alert: t("sessions.create.oauth_failure")
  end

  private

  def redirect_for(outcome)
    case outcome.code
    when :signed_in
      if outcome.problems.include?(:invitation_email_mismatch)
        flash[:alert] = t("registrations.create.invitation_email_mismatch")
      end
      start_new_session_for(outcome.user)
      redirect_to after_authentication_url, notice: t("sessions.create.success")
    when :linked
      redirect_to settings_connected_accounts_path,
        notice: t("omniauth_callbacks.create.linked", provider: outcome.provider_name)
    when :verification_sent
      flash[:confirming_email_for] = outcome.auth.id
      redirect_to settings_connected_accounts_path,
        notice: t("omniauth_callbacks.create.pending",
                  email: outcome.email, provider: outcome.provider_name)
    when :verification_resent
      redirect_to fallback_path,
        notice: t("omniauth_callbacks.create.pending_resent", email: outcome.email)
    when :pending_in_progress
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.pending_in_progress",
                 provider: outcome.provider_name, email: outcome.email)
    when :already_linked
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.already_linked", provider: outcome.provider_name)
    when :collision
      redirect_to settings_connected_accounts_path,
        alert: t("omniauth_callbacks.create.collision_other_user", provider: outcome.provider_name)
    when :signups_closed
      redirect_to new_session_path,
        alert: t("registrations.closed.oauth_blocked"),
        status: :see_other
    when :unverified_pending
      redirect_to new_session_path,
        notice: t("omniauth_callbacks.create.unverified_email_pending", email: outcome.email)
    when :failed
      redirect_to fallback_path,
        alert: t("omniauth_callbacks.create.linking_failed")
    else
      raise ArgumentError, "unknown OauthLink outcome: #{outcome.code.inspect}"
    end
  end

  def fallback_path
    Current.user.present? ? settings_connected_accounts_path : new_session_path
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

  # Fork deviation (MiClassrooms Phase 0 Task 7): Google domain allowlist —
  # case-insensitive EXACT match against the domain part of the OAuth-supplied
  # email — never end_with?/include? substring matching, which would let
  # "evilumich.edu" or "umich.edu.evil.com" slip past a naive check. The
  # email is canonicalized through EmailNormalizer.normalize (NFC + strip +
  # downcase + punycoded domain) and AuthConfig.allowed_google_domains applies
  # the identical canonicalization to each allowlist entry at read time, so
  # both sides of the include? compare in the same form. An empty allowlist
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
  # Authentication row. Gated on the normalized provider (not merely
  # "id_token present") because Google's strategy is also OIDC-based and
  # populates credentials.id_token too — without this guard, signing in via
  # Google would incorrectly route sign-out through Okta's
  # end_session_endpoint.
  def stash_okta_logout_state(identity)
    return unless identity.provider == "okta"

    session[:okta_id_token] = identity.id_token if identity.id_token.present?
  end
end
