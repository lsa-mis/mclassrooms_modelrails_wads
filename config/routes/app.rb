# Fork-owned: your product's routes live here. Upstream (modelrails_base)
# freezes this file after creation — add and rewrite routes freely in a fork
# without merge conflicts on config/routes.rb. See /docs/developer/forking.

root "pages#home"
get "about", to: "pages#about"
get "privacy", to: "pages#privacy"
get "contact", to: "pages#contact"

# Find a Room (MiClassrooms Phase 3 Task 4, Brief §5.2). filters-glossary is
# drawn here alongside find-a-room even though CharacteristicsController#glossary
# ships in a later phase-3 task — Rails routes are inert data until dispatched,
# so pre-drawing the named route now lets Task 5's glossary link use
# `filters_glossary_path` without a second routes.rb touch.
get "find-a-room",      to: "rooms#index",              as: :find_a_room
get "filters-glossary", to: "characteristics#glossary", as: :filters_glossary

# Room detail (MiClassrooms Phase 4 Task 3, contract). Only #show ships this
# task — #edit/#update land in Task 7, #floor_plan in Task 6 — but all three
# routes are drawn now per the contract; nothing links to the unimplemented
# actions yet, and no routing-conformance spec in this checkout asserts every
# drawn route resolves to an existing action (verified: no such spec exists).
resources :rooms, only: [ :show, :edit, :update ] do
  get :floor_plan, on: :member
end

# Fork deviation (MiClassrooms Phase 0 Task 8): non-production test login for
# accessibility crawlers — Siteimprove can't complete Google/Okta SSO. Drawn only when
# AuthConfig.test_login_enabled? is true at boot — i.e. never in production,
# and never without a configured TEST_LOGIN_TOKEN — so the route is
# structurally absent (not merely guarded) rather than drawn-and-blocked.
# See TestLoginsController for the request-time defenses.
if AuthConfig.test_login_enabled?
  get "test_login", to: "test_logins#create"
end
