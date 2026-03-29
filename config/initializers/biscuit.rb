# frozen_string_literal: true

# GDPR Cookie Consent Configuration
#
# Biscuit provides the consent UI and cookie storage. It does NOT auto-block
# third-party scripts — you must conditionally load them:
#
#   <% if biscuit_allowed?(:analytics) %>
#     <!-- Google Analytics or similar -->
#   <% end %>

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
