Rails.application.config.middleware.use OmniAuth::Builder do
  google_id = Rails.application.credentials.dig(:oauth, :google, :client_id)
  google_secret = Rails.application.credentials.dig(:oauth, :google, :client_secret)
  if google_id.present? || Rails.env.test?
    provider :google_oauth2,
      google_id || "test",
      google_secret || "test",
      scope: "email,profile"
  end

  github_id = Rails.application.credentials.dig(:oauth, :github, :client_id)
  github_secret = Rails.application.credentials.dig(:oauth, :github, :client_secret)
  if github_id.present? || Rails.env.test?
    provider :github,
      github_id || "test",
      github_secret || "test",
      scope: "user:email"
  end

  # Okta (Task 6, MiClassrooms Phase 0): unlike Google/GitHub above, Okta is
  # configured via ENV (OKTA_ISSUER/OKTA_CLIENT_ID/OKTA_CLIENT_SECRET, see
  # .env.example) rather than Rails credentials — this fork's IdP is set per
  # deployment (a university's Okta org), not a checked-in template default.
  okta_issuer = ENV["OKTA_ISSUER"]
  if okta_issuer.present? || Rails.env.test?
    # redirect_uri must be a fixed, exact string — Okta whitelists callback
    # URLs in its admin console, unlike Google/GitHub's strategies above which
    # derive the callback from the live request host. Built from the same
    # app-origin derivation Passkeys.origin uses (config/initializers/webauthn.rb
    # — the app's mailer host/port, not a dedicated APP_URL var, which this fork
    # doesn't have). Duplicated rather than calling Passkeys.origin directly:
    # initializers load alphabetically, so "omniauth" runs before "webauthn" and
    # the Passkeys module wouldn't exist yet.
    mailer_opts = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
    app_host = mailer_opts[:host] || "localhost"
    app_port = mailer_opts[:port]
    app_scheme = app_host.start_with?("localhost", "127.0.0.1") ? "http" : "https"
    app_host = "#{app_host}:#{app_port}" if app_port.present? && [ 80, 443 ].exclude?(app_port.to_i)
    app_origin = "#{app_scheme}://#{app_host}"

    provider :openid_connect,
      name: :okta,
      issuer: okta_issuer || "https://okta.test",
      discovery: true,
      scope: %i[openid email profile],
      response_type: :code,
      uid_field: "preferred_username",
      client_options: {
        identifier: ENV["OKTA_CLIENT_ID"] || "test",
        secret: ENV["OKTA_CLIENT_SECRET"] || "test",
        redirect_uri: "#{app_origin}/auth/okta/callback"
      }
  end
end

OmniAuth.config.allowed_request_methods = [ :post ]
OmniAuth.config.silence_get_warning = true
