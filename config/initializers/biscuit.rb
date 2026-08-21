# frozen_string_literal: true

Biscuit.configure do |config|
  config.categories = {
    necessary:   { required: true },
    analytics:   { required: false },
    preferences: { required: false },
    marketing:   { required: false }
  }

  config.cookie_name = "biscuit_consent"
  config.cookie_expires_days = 365
  config.cookie_same_site = "Lax"
  config.position = :bottom
  config.privacy_policy_url = "/privacy"
end
