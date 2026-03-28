module OauthHelper
  PROVIDER_CONFIG = {
    google_oauth2: { name: "Google", icon: "google" },
    github: { name: "GitHub", icon: "github" }
  }.freeze

  def enabled_oauth_providers
    PROVIDER_CONFIG.select do |provider_key, _config|
      case provider_key
      when :google_oauth2
        Rails.application.credentials.dig(:google, :client_id).present?
      when :github
        Rails.application.credentials.dig(:github, :client_id).present?
      end
    end
  end

  def oauth_enabled?
    enabled_oauth_providers.any?
  end
end
