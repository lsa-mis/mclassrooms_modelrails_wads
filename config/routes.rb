Rails.application.routes.draw do
  mount Markdowndocs::Engine, at: "/docs"
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
  mount Lookbook::Engine, at: "/lookbook" if Rails.env.development?
  mount Biscuit::Engine, at: "/biscuit"

  # Shadows the Active Storage engine's UNAUTHENTICATED direct-upload endpoint
  # (SEC-7). Engine/railtie routes load after this file, so this declaration
  # wins; the engine's rails_direct_uploads_url helper still points here.
  post "/rails/active_storage/direct_uploads" => "direct_uploads#create"

  # Test-only harness exercising every form-draft field archetype (the real
  # adoption forms are text-only). Controller lives in spec/support/harness.
  resource :draft_harness, only: %i[show create], controller: "draft_harness" if Rails.env.test?

  resource :session do
    scope module: :sessions do
      # The two steps of email-first sign-in (#1007): the lookup sends the right
      # link and renders the next step; the password step's form posts to sessions#create.
      resource :lookup, only: [ :create ]
      resource :password, only: [ :new ]
    end
  end
  resource :email_verification, only: [ :new, :show, :create ]

  # A WebAuthn ceremony is two creates on two nouns (#1007): the challenge the
  # authenticator signs, then what the signature earns — a credential, a
  # session, or a confirmation of the current one.
  namespace :passkeys do
    namespace :registration do
      resource :challenge, only: :create
      resource :credential, only: :create
    end
    namespace :authentication do
      resource :challenge, only: :create
      resource :session, only: :create
    end
    namespace :reauthentication do
      resource :challenge, only: :create
      resource :confirmation, only: :create
    end
  end

  resource :email_verification_resend, only: [ :create ]

  resource :magic_link, only: [ :create ]
  resource :password_reset, only: [ :create ]
  # GET only renders a confirmation; the session is a nested resource whose
  # create is the POST, so a mail scanner or prefetch can't burn the token or
  # sign anyone in (SEC-5). Registration keeps its POST on the callback itself.
  resources :magic_link_callbacks, param: :token, path: "magic_link_callback", only: [ :show ] do
    resource :session, only: [ :create ], module: :magic_link_callbacks
  end
  post "magic_link_callback/:token", to: "magic_link_callbacks#create"

  get "/auth/:provider/callback", to: "omniauth_callbacks#create"
  # OmniAuth fixes this path (on_failure); the page is its own controller's show (#1007).
  get "/auth/failure", to: "omniauth_failures#show", as: :omniauth_failure

  resource :passkey_prompt, only: [ :update ]

  # A pre-existing user's parked open-link join (Flow B): accept it (create) or
  # dismiss it (destroy). Both act only on the signed-in user's own session.
  resource :pending_join, only: [ :create, :destroy ]

  namespace :settings do
    resource :profile, only: [ :edit, :update ]
    resource :password, only: [ :new, :create, :edit, :update, :destroy ]
    # show is the picker hub the profile page lazy-loads (#1007).
    resource :avatar, only: [ :show, :update, :destroy ]
    resource :theme_preference, only: [ :edit, :update ]
    resource :notification_preferences, only: [ :edit, :update ]
    namespace :preferences do
      resource :timezone, only: [ :update ]
    end
    resources :sessions, only: [ :index, :destroy ]
    resource :other_sessions, only: [ :destroy ]
    resource :reauthentication, only: [ :new, :create ]
    resource :reauthentication_code, only: [ :create ]
    resources :passkeys, only: [ :index, :destroy ]
    resources :connected_accounts, only: [ :index, :destroy ] do
      # Resending the verification email is a resend, created (#1007).
      scope module: :connected_accounts do
        resource :verification_resend, only: :create
      end
    end
    resource :connected_account_verification, only: [ :show, :create ], path: "connected_accounts/verify"
    # Legacy path-token route, kept for one token lifetime (24 h) after the
    # 2026-09 deploy so in-flight verification emails still land; remove after
    # that deploy plus one day. Renders the confirmation only (#950/#916).
    get "connected_accounts/verify/:token", to: "connected_account_verifications#show", as: :legacy_verify_settings_connected_accounts
    resource :email_confirmation, only: [ :show, :destroy ]
    resources :notifications, only: [ :index, :update ] do
      # POST-only open-and-mark-read (#686): a GET here MUTATED (read_at), so
      # link prefetchers and mail scanners marked notifications read — the
      # same class of route the magic-link comment below refuses.
      scope module: :notifications do
        resource :reading, only: :create
      end
    end
    # Mark all read: readings for every unread notification, created at once
    # (#1007) — the bulk twin of the per-notification reading above.
    resource :notification_readings, only: :create
  end

  resources :workspaces, param: :slug do
    scope module: :workspaces do
      # Archived is a state, so it is a singular resource: POST archives, DELETE restores (#1007).
      resource :archival, only: [ :create, :destroy ]
      # The logo picker hub; saves post to workspaces#update, where the logo lives (#1007).
      resource :logo, only: [ :show ]
      resources :members, only: [ :index, :edit, :update, :destroy ] do
        # Deactivating is members#destroy; reactivating creates a reactivation (#1007).
        scope module: :members do
          resource :reactivation, only: :create
          resource :ownership_transfer, only: :create
        end
      end
      resources :invitations, only: [ :new, :create, :destroy ] do
        scope module: :invitations do
          resource :resend, only: :create
        end
      end
      resources :join_links, only: [ :create, :destroy ]
      # Token in URL so the link is shareable; GET shows a confirmation page
      # (prevents URL prefetch / link unfurlers from triggering a join), POST
      # executes. Both use the same `workspace_join_path` helper.
      get  "joins/:token", to: "joins#show",   as: :join
      post "joins/:token", to: "joins#create"
      resource :settings, only: [ :edit, :update ]
    end
  end

  get "invitations/:token/accept", to: "invitation_accepts#show", as: :accept_invitation
  post "invitations/:token/accept", to: "invitation_accepts#create"
  get "invitations/:token/decline", to: "invitation_declines#show", as: :decline_invitation
  post "invitations/:token/decline", to: "invitation_declines#create"
  # Blocking an inviter is reached only from the signed link in the invitee's
  # own invitation email; the token travels as a query parameter (#951/#916).
  resource :invitation_block, only: [ :show, :create ]

  resource :onboarding, only: %i[show update]
  namespace :onboarding do
    resource :workspace, only: %i[new create]
  end

  # Fork seam: product routes (root, marketing pages, your features) live in
  # the fork-owned config/routes/app.rb. See /docs/developer/forking.
  draw(:app)

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
