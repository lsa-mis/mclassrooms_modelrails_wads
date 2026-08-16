# Single home for OAuth provider knowledge (#312): CSP form-action,
# omniauth.rb, and oauth_helper.rb all derive from it, and the `0_` prefix
# loads it before those consumers. A provider change must also update the
# cross-check hash in spec/initializers/content_security_policy_spec.rb —
# see /docs/developer/security (OAuth Security).
Rails.application.config.x.oauth_providers = {
  google_oauth2: { name: "Google", icon: "google", form_action_host: "https://accounts.google.com" },
  github:        { name: "GitHub", icon: "github", form_action_host: "https://github.com" },
  # Fork addition (MiClassrooms Phase 0 Task 7): Okta's consent host is a
  # wildcard rather than a fixed domain because it's org-specific — each Okta
  # customer gets their own "https://<org>.okta.com" subdomain, set at deploy
  # time via OKTA_ISSUER (see config/initializers/omniauth.rb). Deployments
  # using an Okta custom domain, or an *.oktapreview.com sandbox org, need
  # that host here instead.
  okta:          { name: "Okta", icon: "okta", form_action_host: "https://*.okta.com" }
}.freeze
