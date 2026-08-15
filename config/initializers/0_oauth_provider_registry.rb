# The single home for OAuth provider knowledge (#312). Three consumers derive
# from this registry rather than repeating it:
#
#   - config/initializers/content_security_policy.rb builds form_action from
#     form_action_host (CSP evaluates the whole redirect chain, and a swapped
#     provider whose consent host is missing fails as a SILENT browser-side
#     block — no server error, nothing in the logs, undebuggable from the
#     symptom)
#   - config/initializers/omniauth.rb declares strategies for these keys
#   - app/helpers/oauth_helper.rb renders buttons from name/icon
#
# Duplicated knowledge does not announce its drift; it just waits. The `0_`
# prefix makes this initializer sort before its consumers (initializers run
# in filename order), and it lives on config.x because app constants are not
# referenceable at initializer time (Zeitwerk).
#
# Adding/swapping a provider: add the entry here (form_action_host is the
# consent-screen origin the browser is redirected to), declare the strategy
# in omniauth.rb, and update the literal cross-check hash in
# spec/initializers/content_security_policy_spec.rb — the spec fails loudly
# until you do, which is the point (double-entry bookkeeping on a
# security-relevant value).
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
