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
end

OmniAuth.config.allowed_request_methods = [ :post ]
OmniAuth.config.silence_get_warning = true
