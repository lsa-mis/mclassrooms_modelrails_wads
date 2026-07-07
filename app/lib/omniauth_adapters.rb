# Maps OmniAuth strategy names to canonical Authentication#provider enum values.
# OmniAuth strategies often have names like "google_oauth2" while our enum stores
# the simpler "google". This adapter centralizes the translation so the controller
# stays focused on flow logic rather than naming-quirk normalization.
#
# Okta needs no entry: its `provider :openid_connect, name: :okta` registration
# (config/initializers/omniauth.rb) already emits auth_hash.provider == "okta",
# which matches the enum value directly — the PROVIDER_MAP.fetch default
# (pass-through) handles it without a mapping.
module OmniauthAdapters
  PROVIDER_MAP = { "google_oauth2" => "google" }.freeze

  def self.normalize_provider(strategy_name)
    PROVIDER_MAP.fetch(strategy_name, strategy_name)
  end
end
