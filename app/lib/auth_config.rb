# Posture-aware reader for the SSO-only auth configuration (MiClassrooms
# Phase 0 Task 7). Centralizes the few call sites that need to ask "are we
# SSO-only?" or "which Google domains are allowed?", mirroring TenancyConfig's
# role for the tenancy preset (app/lib/tenancy_config.rb).
module AuthConfig
  module_function

  # When true: the sign-in page shows only the configured SSO buttons
  # (Google + Okta) and hides the email/password/magic-link lookup form and
  # the passkey prompt (app/views/sessions/new.html.erb). Also excludes the
  # GitHub OAuth button from OauthHelper#enabled_oauth_providers even though
  # its strategy stays configured (config/initializers/omniauth.rb) — see
  # config/application.rb for the AUTH_SSO_ONLY env knob (default:
  # Rails.env.production?).
  #
  # Deliberately UI-scoped: the underlying routes/controllers
  # (SessionsController#lookup, MagicLinkCallbacksController) stay reachable
  # even when this is true. That's not an oversight — the seeded workspace
  # Owner (TENANCY_OWNER_EMAIL, see db/seeds.rb) is provisioned with a
  # password-set link, not SSO, and needs a working break-glass sign-in path
  # that doesn't depend on Google/Okta being reachable. See the comment atop
  # app/views/sessions/new.html.erb for the same rationale at the call site.
  def sso_only?
    Rails.configuration.x.auth.sso_only
  end

  # Comma-separated ALLOWED_GOOGLE_DOMAINS env, pre-split/downcased into an
  # array of bare domains (config/application.rb). Empty means "disabled" —
  # every domain passes — which is the dev-friendly default. Never applies to
  # Okta: org membership is Okta's own gate (see
  # OmniauthCallbacksController#google_domain_allowed?).
  def allowed_google_domains
    Rails.configuration.x.auth.allowed_google_domains
  end
end
