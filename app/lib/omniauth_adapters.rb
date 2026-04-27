# Maps OmniAuth strategy names to canonical Authentication#provider enum values.
# OmniAuth strategies often have names like "google_oauth2" while our enum stores
# the simpler "google". This adapter centralizes the translation so the controller
# stays focused on flow logic rather than naming-quirk normalization.
module OmniauthAdapters
  PROVIDER_MAP = { "google_oauth2" => "google" }.freeze

  def self.normalize_provider(strategy_name)
    PROVIDER_MAP.fetch(strategy_name, strategy_name)
  end
end
