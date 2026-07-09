# rails_blob_url / rails_representation_url (RoomPresenter#as_json, phase 4) resolve
# through named routes, which need a default :host — but RoomPresenter runs outside a
# request, so it can't borrow the request's host. Set it once at boot from the same
# per-environment mailer host webauthn.rb / omniauth.rb already reuse, rather than
# learning it from whichever request arrives first (wrong port; first-Host-wins).
# Single-host topology (CLAUDE.md) → one deterministic value; production derives it
# from RAILS_HOST via config/environments/production.rb.
url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
Rails.application.routes.default_url_options.merge!(url_options)
