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

  # Comma-separated ALLOWED_GOOGLE_DOMAINS env, split at boot
  # (config/application.rb) and canonicalized here at read time: NFC + strip
  # + downcase + punycode via EmailNormalizer.punycode_domain — the exact
  # canonical form EmailNormalizer.normalize produces for an email's domain
  # part, so OmniauthCallbacksController#google_domain_allowed? compares
  # like against like. Normalization lives here rather than in
  # config/application.rb because EmailNormalizer is an app/lib autoloadable
  # constant, unavailable during application-class definition (same boot
  # constraint documented in config/initializers/tenancy.rb re: Role).
  # Empty means "disabled" — every domain passes — the dev-friendly default.
  # Never applies to Okta: org membership is Okta's own gate.
  def allowed_google_domains
    Rails.configuration.x.auth.allowed_google_domains.filter_map do |entry|
      domain = entry.to_s.unicode_normalize(:nfc).strip.downcase
      next if domain.empty?

      EmailNormalizer.punycode_domain(domain)
    end
  end

  # Non-production test login for accessibility crawlers (MiClassrooms Phase
  # 0 Task 8): Siteimprove can't complete Google/Okta SSO, so non-production
  # environments expose GET /test_login?token=... as a token-gated backdoor
  # (TestLoginsController). This predicate gates whether config/routes/app.rb
  # DRAWS the route at all — the route is structurally absent (not merely
  # guarded) whenever this is false, most importantly in production.
  #
  # Deliberately read fresh from Rails.env/ENV on every call rather than
  # cached off Rails.configuration.x.auth (contrast sso_only?/
  # allowed_google_domains above, which snapshot ENV once at boot in
  # config/application.rb): specs need to flip Rails.env/ENV per example to
  # pin this predicate directly (spec/lib/auth_config_spec.rb) without
  # reloading routes. The route itself is still boot-time-frozen — see
  # TestLoginsController for the independent, request-time re-check of
  # token presence, which is what actually protects a route that stays
  # drawn across the life of a booted process even if ENV later changes.
  def test_login_enabled?
    !Rails.env.production? && test_login_token.present?
  end

  # The configured shared secret, or nil/blank when unset. Centralized here
  # (rather than reading ENV directly in both config/routes/app.rb and
  # TestLoginsController) so there's one place documenting the var.
  def test_login_token
    ENV["TEST_LOGIN_TOKEN"]
  end

  # TEST_LOGIN_ADMIN=true grants the test user the Admin role in its
  # workspace membership instead of the default Viewer; unset (or any other
  # value) downgrades back to Viewer on the next test login. See
  # TestLoginsController#grant_test_role.
  def test_login_admin?
    ENV["TEST_LOGIN_ADMIN"] == "true"
  end

  # Fork deviation (MiClassrooms Phase 0 Task 6): Okta issuer URL — centralizes
  # the ENV var name so config/initializers/omniauth.rb, OauthHelper#enabled_oauth_providers,
  # and SessionsController#okta_end_session_url don't each hardcode
  # "OKTA_ISSUER" independently. Read fresh from ENV on every call — same
  # rationale as test_login_token above — rather than baked into
  # Rails.configuration.x.auth at boot: config/initializers/omniauth.rb reads
  # this from inside the OmniAuth::Builder block, which is only evaluated
  # when the middleware stack is built (after config/application.rb's config.x
  # assignments would even help), and Okta org config is otherwise
  # ENV-only (unlike Google/GitHub, which read Rails credentials — see the
  # initializer for why). No value here means Okta isn't configured for this
  # deployment.
  def okta_issuer
    ENV["OKTA_ISSUER"]
  end
end
