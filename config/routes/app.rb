# Fork-owned (merge=ours): this product's routes. See /docs/developer/forking.

root to: "pages#show", defaults: { id: "home" }
resources :pages, only: :show, path: "", constraints: { id: /about|privacy|contact/ }

get "find-a-room",      to: "rooms#index",           as: :find_a_room
get "filters-glossary", to: "characteristics#index", as: :filters_glossary

get "rooms", to: redirect("/find-a-room")

resources :saved_rooms, only: [ :create, :destroy ]

resources :rooms, only: [ :show, :edit, :update ] do
  scope module: :rooms do
    resource :floor_plan, only: :show
    resource :panorama, only: [ :update, :destroy ]
    resource :seating_chart, only: [ :update, :destroy ]
    resource :gallery, only: :update
    resources :photos, only: :destroy
    resource :hiding, only: [ :create, :destroy ]
  end
end

resources :buildings, only: [ :index, :show, :edit, :update ] do
  scope module: :buildings do
    resource :hiding, only: [ :create, :destroy ]
  end
end

# Not nested: a note names its own notable, and NotePolicy authorizes through it.
resources :notes, only: [ :create, :update, :destroy ]

# The feedback modal posts here; our LsaTdxFeedback::FeedbackController override takes signed-out reports.
mount LsaTdxFeedback::Engine => "/lsa_tdx_feedback"

namespace :admin do
  resources :bulk_uploads, only: [ :new, :create ]
  resources :announcements, except: [ :show ]
  resources :editor_assignments, only: [ :index, :new, :create, :destroy ]
  resources :characteristic_display_rules, except: [ :show ]
  resources :unit_display_names, except: [ :show ]
  resources :sync_scope_rules, except: [ :show ]
  resources :sync_runs, only: %i[index show]
end

namespace :operations do
  resources :sync_runs, only: %i[index show create] do
    scope module: :sync_runs do
      resource :resumption, only: :create
    end
  end
end

# Drawn only when test login is enabled, never in production: Siteimprove's crawler can only send a GET.
if AuthConfig.test_login_enabled?
  get "test_login", to: "test_logins#create"
end

# D18 legacy URLs, drawn last so a catch-all never shadows a product route.
draw(:legacy)
