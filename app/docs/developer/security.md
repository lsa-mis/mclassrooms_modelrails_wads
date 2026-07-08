---
title: Security
description: Security configuration, recommendations, and best practices for ModelRails
keywords: rate limiting account locking headers csp password oauth rack attack https bearer token
---

# Security

## Built-In Protections

### Rate Limiting

Auth endpoints are rate-limited via Rails 8 `rate_limit` DSL:

| Endpoint | Limit | Window |
|----------|-------|--------|
| POST /session (sign in / email-first lookup) | 10 requests | 3 minutes |
| POST /passwords (reset) | 10 requests | 3 minutes |
| POST /magic_links (magic link) | 5 requests | 3 minutes |

### Account Locking

After 5 failed login attempts, accounts are locked for 1 hour. Auto-unlock occurs after the lockout period. Admin rake tasks:

```bash
rails users:unlock[email@example.com]     # Unlock a locked account
rails users:verify[email@example.com]     # Manually verify an email
rails users:suspend[email@example.com]    # Suspend an account (destroys sessions, deactivates memberships)
```

### Security Headers

Configured in `config/initializers/security_headers.rb`:

- `X-Frame-Options: SAMEORIGIN` — prevents clickjacking
- `X-Content-Type-Options: nosniff` — prevents MIME sniffing
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy` — disables camera, microphone, geolocation by default
- Content Security Policy via `content_security_policy.rb` (enforced in development and production, report-only in test for Playwright compatibility)

### Password Security

- 12-character minimum
- Pwned password check (Have I Been Pwned API)
- Account recovery issues a single-use `MagicLinkToken` (`set_password` intent, 15-minute expiry), not a stateless reset token

### OAuth Security

- OAuth email matching requires a verified email authentication on the existing account
- Unverified accounts are not linked — a new user is created instead

### Activity Tracking

The `Trackable` concern logs all model changes to `ActivityLog`. Sensitive attributes are automatically stripped from metadata:

- `token`, `password_digest`
- `oauth_token`, `oauth_refresh_token`

### Invitation Bearer-Token Protection

`Invitation.consume!` enforces an `EmailMismatch` guard: if the invitation was addressed to a specific email and the redeeming user's proven email does not match, redemption is refused with `Invitation::EmailMismatch`. This prevents a leaked invite link from being claimed by a different email address (`app/models/invitation.rb`).

## Production Recommendations

### Rack::Attack (IP-Level Rate Limiting)

For production deployments, add [Rack::Attack](https://github.com/rack/rack-attack) for IP-level blocking across controllers:

```ruby
# Gemfile
gem "rack-attack"

# config/initializers/rack_attack.rb
Rack::Attack.throttle("logins/ip", limit: 20, period: 1.hour) do |req|
  req.ip if req.path == "/session" && req.post?
end
```

### Top Secret (PII Filtering)

For apps handling personally identifiable information in free-form text (user-generated content, chat messages), consider [Top Secret](https://github.com/thoughtbot/top_secret) to filter PII before sending to external APIs or LLMs:

```ruby
# Gemfile
gem "top_secret"

# Filter user input before API calls
filtered = TopSecret.filter(user_input)
```

This is especially relevant for:
- `ActivityLog` metadata containing free-form text
- `Document` content processed by search indexes or AI features
- Any data sent to third-party analytics or monitoring

### HTTPS and HSTS

Configure in `config/environments/production.rb`:

```ruby
config.force_ssl = true
config.ssl_options = { hsts: { subdomains: true, preload: true, expires: 1.year } }
```
