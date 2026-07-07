module OauthHelper
  PROVIDER_CONFIG = {
    google_oauth2: { name: "Google", icon: "google" },
    github: { name: "GitHub", icon: "github" },
    # Okta reads its client id from ENV (OKTA_ISSUER), not Rails credentials
    # like the two providers above — see config/initializers/omniauth.rb.
    okta: { name: "Okta", icon: "okta" }
  }.freeze

  def enabled_oauth_providers
    PROVIDER_CONFIG.select do |provider_key, _config|
      case provider_key
      when :google_oauth2
        Rails.application.credentials.dig(:oauth, :google, :client_id).present?
      when :github
        Rails.application.credentials.dig(:oauth, :github, :client_id).present?
      when :okta
        ENV["OKTA_ISSUER"].present?
      end
    end
  end

  def oauth_enabled?
    enabled_oauth_providers.any?
  end
end
