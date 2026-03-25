Rails.application.routes.draw do
  resource :session
  resource :registration, only: [:new, :create]
  resource :email_verification, only: [:show]
  resources :passwords, param: :token

  resource :email_verification_resend, only: [:create]

  get "/auth/:provider/callback", to: "omniauth_callbacks#create"
  get "/auth/failure", to: "omniauth_callbacks#failure"

  namespace :account do
    resource :profile, only: [:edit, :update]
    resource :password, only: [:new, :create]
    resource :avatar, only: [:update, :destroy]
    resource :theme_preference, only: [:update]
    resources :connected_accounts, only: [:index, :destroy]
  end

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
