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

# Fork deviation (MiClassrooms Phase 0 final-review C1): fail-open guard —
# production with Google OAuth credentials configured, SSO-only enabled, and an EMPTY
# ALLOWED_GOOGLE_DOMAINS allowlist is a fail-open misconfiguration — with no
# domains configured, OmniauthCallbacksController#google_domain_allowed? (and,
# for new users, #sso_signup_bypass?) treat the allowlist as disabled (every
# domain passes / the institutional gate is unarmed), so ANY Google account
# could sign in — and self-provision — on what's meant to be a closed,
# SSO-only instance. Raise at boot rather than let this ship silently.
# Scoped to production (dev/test routinely configure Google with placeholder
# credentials and no allowlist) and to the SSO-only + Google-configured
# combination (Google without SSO-only, or SSO-only without Google, don't hit
# this failure mode). Reads Rails.configuration.x.auth directly rather than
# through AuthConfig, like the ALLOWED_GOOGLE_DOMAINS check above — see
# config/initializers/tenancy.rb for why an autoloaded app/lib constant isn't
# safe to reference at this point in boot.
if Rails.env.production? &&
   Rails.application.credentials.dig(:oauth, :google, :client_id).present? &&
   Rails.configuration.x.auth.sso_only &&
   Rails.configuration.x.auth.allowed_google_domains.empty?
  raise "AUTH_SSO_ONLY is true with Google OAuth configured, but ALLOWED_GOOGLE_DOMAINS is empty — " \
        "any Google account could self-provision on this SSO-only instance. Set ALLOWED_GOOGLE_DOMAINS " \
        "to the allowed domains, or unset the Google OAuth credentials."
end
