require "rails_helper"

RSpec.describe "Content Security Policy" do
  let(:policy) { Rails.application.config.content_security_policy }
  let(:form_action) { policy.directives["form-action"] || [] }

  # When you add a new OAuth provider to OauthHelper::PROVIDER_CONFIG,
  # add the provider's consent-screen host to the hash below AND to
  # config/initializers/content_security_policy.rb's form_action directive.
  EXPECTED_OAUTH_HOSTS_BY_PROVIDER = {
    google_oauth2: "https://accounts.google.com",
    github:        "https://github.com",
    okta:          "https://*.okta.com"
  }.freeze

  it "allows form-action to every configured OAuth provider host" do
    OauthHelper::PROVIDER_CONFIG.each_key do |provider|
      expected_host = EXPECTED_OAUTH_HOSTS_BY_PROVIDER.fetch(provider) do
        raise <<~MSG.strip
          Missing CSP form-action host for OAuth provider :#{provider}.
          Add it to EXPECTED_OAUTH_HOSTS_BY_PROVIDER in this spec file:
            #{__FILE__}
          AND to config/initializers/content_security_policy.rb's
          policy.form_action call.
        MSG
      end
      expect(form_action).to include(expected_host),
        "CSP form-action must include #{expected_host} for OAuth provider #{provider}"
    end
  end

  it "always includes :self in form-action" do
    expect(form_action).to include(:self).or include("'self'")
  end
end
