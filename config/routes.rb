Rails.application.routes.draw do
  mount Markdowndocs::Engine, at: "/docs"
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
  mount Lookbook::Engine, at: "/lookbook" if Rails.env.development?
  mount Biscuit::Engine, at: "/biscuit"
  resource :session
  resource :registration, only: [ :new, :create ]
  resource :email_verification, only: [ :show ]
  resources :passwords, param: :token

  resource :email_verification_resend, only: [ :create ]

  resource :magic_link, only: [ :create ]
  get "magic_link_callback/:token", to: "magic_link_callbacks#show", as: :magic_link_callback
  post "magic_link_callback/:token", to: "magic_link_callbacks#create"
  post "session/lookup", to: "sessions#lookup", as: :session_lookup

  get "/auth/:provider/callback", to: "omniauth_callbacks#create"
  get "/auth/failure", to: "omniauth_callbacks#failure"

  namespace :account do
    resource :profile, only: [ :edit, :update ]
    resource :password, only: [ :new, :create ]
    resource :avatar, only: [ :update, :destroy ] do
      get :hub
    end
    resource :theme_preference, only: [ :edit, :update ]
    resource :notification_preferences, only: [ :edit, :update ] do
      post :dismiss_banner
    end
    namespace :preferences do
      resource :timezone, only: [ :update ]
    end
    resources :connected_accounts, only: [ :index, :destroy ] do
      member do
        post :resend_verification
      end
      collection do
        get "verify/:token", action: :verify, as: :verify
      end
    end
    resource :email_confirmation, only: [ :show, :destroy ]
    resources :notifications, only: [ :index, :update, :destroy ] do
      member do
        get :open
      end
      collection do
        post :mark_all_read
        delete :destroy_all_read
      end
    end
  end

  resources :workspaces, param: :slug do
    member do
      get :identity_picker_hub
    end
    scope module: :workspaces do
      resources :members, only: [ :index, :edit, :update, :destroy ] do
        member do
          patch :reactivate
          patch :transfer_ownership
        end
      end
      resources :invitations, only: [ :index, :new, :create, :destroy ] do
        member do
          post :resend
        end
      end
      resources :join_links, only: [ :create, :destroy ]
      # Token in URL so the link is shareable; GET shows a confirmation page
      # (prevents URL prefetch / link unfurlers from triggering a join), POST
      # executes. Both use the same `workspace_join_path` helper.
      get  "joins/:token", to: "joins#show",   as: :join
      post "joins/:token", to: "joins#create"
      resource :settings, only: [ :edit, :update ]
      resources :projects, param: :slug do
        scope module: :projects do
          resources :memberships, only: [ :index, :new, :create, :update, :destroy ] do
            member do
              patch :toggle_pin
            end
          end
          resources :invitations, only: [ :new, :create ]
          resources :resources, only: [ :index, :new, :create, :show, :edit, :update, :destroy ] do
            member do
              patch :reposition
            end
          end
        end
      end
    end
  end

  get "invitations/:token/accept", to: "invitation_accepts#show", as: :accept_invitation
  post "invitations/:token/accept", to: "invitation_accepts#create"
  get "invitations/:token/decline", to: "invitation_declines#show", as: :decline_invitation
  post "invitations/:token/decline", to: "invitation_declines#create"

  # Fork seam: product routes (root, marketing pages, your features) live in
  # the fork-owned config/routes/app.rb. See /docs/forking.
  draw(:app)

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
