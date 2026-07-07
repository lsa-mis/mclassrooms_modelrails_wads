# Fork-owned: your product's routes live here. Upstream (modelrails_base)
# freezes this file after creation — add and rewrite routes freely in a fork
# without merge conflicts on config/routes.rb. See /docs/developer/forking.

root "pages#home"
get "about", to: "pages#about"
get "privacy", to: "pages#privacy"
get "contact", to: "pages#contact"

# Non-production test login for accessibility crawlers (MiClassrooms Phase 0
# Task 8): Siteimprove can't complete Google/Okta SSO. Drawn only when
# AuthConfig.test_login_enabled? is true at boot — i.e. never in production,
# and never without a configured TEST_LOGIN_TOKEN — so the route is
# structurally absent (not merely guarded) rather than drawn-and-blocked.
# See TestLoginsController for the request-time defenses.
if AuthConfig.test_login_enabled?
  get "test_login", to: "test_logins#create"
end
