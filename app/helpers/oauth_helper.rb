module OauthHelper
  # Reads the one provider registry (config/initializers/
  # 0_oauth_provider_registry.rb) so buttons, OmniAuth wiring, and the CSP
  # form_action can never drift apart (#312).
  PROVIDER_CONFIG = Rails.application.config.x.oauth_providers

  def enabled_oauth_providers
    PROVIDER_CONFIG.select do |provider_key, _config|
      # Fork deviation (MiClassrooms Phase 0 Task 7): SSO-only posture —
      # GitHub's strategy stays configured (config/initializers/omniauth.rb)
      # so linking an already-signed-in account still works, but its sign-in
      # button is excluded from the posture that offers only Google + Okta. Gated here
      # (the mechanism enabled_oauth_providers already keys on) rather than
      # in the view, so the sign-in page and any other caller of this helper
      # agree automatically.
      next false if provider_key == :github && AuthConfig.sso_only?

      case provider_key
      when :google_oauth2
        Rails.application.credentials.dig(:oauth, :google, :client_id).present?
      when :github
        Rails.application.credentials.dig(:oauth, :github, :client_id).present?
      when :okta
        AuthConfig.okta_issuer.present?
      end
    end
  end

  def oauth_enabled?
    enabled_oauth_providers.any?
  end
end
