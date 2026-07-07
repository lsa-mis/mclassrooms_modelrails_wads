# Validates SSO-only auth configuration at boot so a mistyped ENV value fails
# fast instead of silently falling back to a default. See app/lib/auth_config.rb
# for the posture-aware readers and config/application.rb for the ENV mapping.

if ENV.key?("AUTH_SSO_ONLY") && !%w[true false].include?(ENV["AUTH_SSO_ONLY"])
  raise "Invalid AUTH_SSO_ONLY: #{ENV['AUTH_SSO_ONLY'].inspect}. Must be one of: true, false"
end

# Guard against the common misconfiguration of pasting full email addresses
# (or anything with whitespace) instead of bare domains.
invalid_google_domains = Rails.configuration.x.auth.allowed_google_domains.select do |domain|
  domain.include?("@") || domain.match?(/\s/)
end

if invalid_google_domains.any?
  raise "Invalid ALLOWED_GOOGLE_DOMAINS entries (must be bare domains, not email addresses): " \
        "#{invalid_google_domains.join(', ')}"
end
