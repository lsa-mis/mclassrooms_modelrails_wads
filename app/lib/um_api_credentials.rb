# Bridges the U-M Facilities gateway credentials from Rails encrypted
# credentials (the app's standard secret store — `rails credentials:edit`, the
# `um_api:` key, where Google/SAML/TDX secrets also live) into the ENV vars
# UmApi::Client / UmApi::TokenCache read (UM_API_CLIENT_ID/SECRET/TOKEN_URL/
# BASE_URL). This keeps the single gateway OAuth client encrypted + version-
# controlled instead of as a plaintext .env / Kamal secret, while leaving
# UmApi's ENV-based reads (and their specs) untouched.
#
# Precedence: an explicit ENV value (a dev .env entry, a Kamal secret) ALWAYS
# wins over this bridge, which in turn supplies the gateway-URL defaults when
# credentials don't override them.
module UmApiCredentials
  DEFAULT_TOKEN_URL = "https://gw.api.it.umich.edu/um/oauth2/token".freeze
  DEFAULT_BASE_URL  = "https://gw.api.it.umich.edu/um".freeze

  module_function

  # Populates `env` from `credentials` for any UM_API_* key not already set.
  # Both args are injectable for testing; they default to the real Rails
  # credentials `um_api` section and the process ENV.
  def install!(credentials: Rails.application.credentials.um_api, env: ENV)
    return if credentials.blank?

    # One OAuth client serves every scope (buildings/classrooms/department);
    # the `buildings_` prefix is legacy naming. Prefer scope-neutral keys if a
    # future credentials edit adds them, else fall back to the legacy names.
    values = {
      "UM_API_CLIENT_ID"     => credentials[:client_id]     || credentials[:buildings_client_id],
      "UM_API_CLIENT_SECRET" => credentials[:client_secret] || credentials[:buildings_client_secret],
      "UM_API_TOKEN_URL"     => credentials[:token_url] || DEFAULT_TOKEN_URL,
      "UM_API_BASE_URL"      => credentials[:base_url]  || DEFAULT_BASE_URL
    }

    values.each do |key, value|
      env[key] = value if env[key].blank? && value.present?
    end
  end
end
