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

# Convenience alias (product navigation): users naturally type /rooms
# expecting the room directory; the real index lives at /find-a-room. This
# redirect does not conflict with `resources :rooms` below, which only draws
# /rooms/:id (no #index).
get "rooms", to: redirect("/find-a-room")

# Room detail (MiClassrooms Phase 4 Task 3, contract). Only #show ships this
# task — #edit/#update land in Task 7, #floor_plan in Task 6 — but all three
# routes are drawn now per the contract; nothing links to the unimplemented
# actions yet, and no routing-conformance spec in this checkout asserts every
# drawn route resolves to an existing action (verified: no such spec exists).
# Saved rooms (shortlist): plain REST create/destroy; the toggle button on
# cards and room pages posts here and gets a Turbo Stream back.
resources :saved_rooms, only: [ :create, :destroy ]

resources :rooms, only: [ :show, :edit, :update ] do
  get :floor_plan, on: :member
  member do
    post :hide
    post :unhide
  end
end

# Admin Buildings section (MiClassrooms Phase 4 Task 8, contract). Only
# #index/#show ship this task — #edit/#update land in Task 9 — but all four
# routes are drawn now per the contract, mirroring the `resources :rooms`
# precedent above (nothing links to the unimplemented actions yet). JSON is
# supported on #index/#show only (the contract doesn't require it on
# #edit/#update).
#
# hide/unhide (Phase 5 Task 5, Brief §14.1): admin-only visibility flow,
# mirroring the `resources :rooms` member routes above.
resources :buildings, only: [ :index, :show, :edit, :update ] do
  member do
    post :hide
    post :unhide
  end
end

# Notes & alerts (MiClassrooms Phase 5 Task 7, Brief §14.1, D15): a product
# resource, NOT nested under rooms/buildings — a note's own
# notable_type/notable_id (hidden fields on notes/_form.html.erb) says which
# record it's on, mirroring how NotePolicy authorizes off `record.notable`
# rather than a parent resource in the URL. Only create/update/destroy ship
# here — notes render inline via notes/_list (rendered from rooms#show), so
# there is no #index/#show/#edit; edit is an inline Turbo Stream swap on the
# same page, not a separate route.
resources :notes, only: [ :create, :update, :destroy ]

# Feedback / support (MiClassrooms Phase 8 Task 1-2, D17): a signed-in feedback
# form that files a TeamDynamix ticket via the lsa_tdx_feedback gem's TicketClient
# (Feedback::Submit), with an email-to-admins fallback when TDX isn't configured.
# Singular resource — one form, no persisted record to show/edit.
resource :feedback, only: [ :new, :create ]

# Admin bulk upload (MiClassrooms Phase 4 Task 11, Brief §5.3): a stateless
# drop -> review -> commit flow with NO persisted model, so only :new/:create
# are drawn — a deliberate SUBSET of the roadmap contract's bare
# `resources :bulk_uploads`. There is no row to #show/#edit/#update/#destroy;
# the "review" step is just #create re-rendering a template (params[:confirmed]
# unset) rather than a separate route, and the final commit redirects back to
# #new rather than to a #show that doesn't exist.
#
# Admin announcements (MiClassrooms Phase 5 Task 8, Brief §14.1): the three
# fixed slots (home_page/find_a_room_page/about_page). No #show: the index
# already renders each slot's filled/empty state inline, so there is no
# separate detail page to link to — a deliberate SUBSET of the seven Pundit
# actions AnnouncementPolicy defines, mirroring the `resources :bulk_uploads`
# precedent just above.
#
# Admin editor assignments (MiClassrooms Phase 5 Task 9, Brief §14.1): grant/
# revoke unit editor claims. No #show/#edit/#update — a grant/revoke pair has
# nothing to edit (EditorAssignmentPolicy defines exactly index?/new?/
# create?/destroy?, mirroring the announcements precedent's deliberate
# subset).
#
# Admin reference data (MiClassrooms Phase 5 Task 11, Brief §11.4/§14.1):
# CharacteristicDisplayRule/UnitDisplayName/SyncScopeRule — standard REST
# minus #show (the index already renders every row's editable fields inline;
# there is no separate detail page), mirroring the announcements precedent.
namespace :admin do
  resources :bulk_uploads, only: [ :new, :create ]
  resources :announcements, except: [ :show ]
  resources :editor_assignments, only: [ :index, :new, :create, :destroy ]
  resources :characteristic_display_rules, except: [ :show ]
  resources :unit_display_names, except: [ :show ]
  resources :sync_scope_rules, except: [ :show ]
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

# D18 (Brief §5.9): retired Classroom Database URLs. Drawn last so the legacy
# catch-alls (e.g. /classrooms/:facility_code) never shadow a product route.
draw(:legacy)
