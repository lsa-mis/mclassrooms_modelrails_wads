Rails.application.routes.draw do
  mount Markdowndocs::Engine, at: "/docs"
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
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
    resource :theme_preference, only: [ :update ]
    resources :connected_accounts, only: [ :index, :destroy ]
    resource :email_confirmation, only: [ :show, :destroy ]
  end

  resources :workspaces, param: :slug do
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
      resource :settings, only: [ :edit, :update ]
      resource :branding, only: [ :edit, :update, :destroy ] do
        get :hub
      end
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

  root "pages#home"
  get "about", to: "pages#about"
  get "privacy", to: "pages#privacy"
  get "contact", to: "pages#contact"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
