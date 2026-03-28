---
title: Security
description: Security configuration, recommendations, and best practices for ModelRails
keywords: rate limiting account locking headers csp password oauth rack attack https
---

# Security

## Built-In Protections

### Rate Limiting

Auth endpoints are rate-limited via Rails 8 `rate_limit` DSL:

| Endpoint | Limit | Window |
|----------|-------|--------|
| POST /session (login) | 10 requests | 3 minutes |
| POST /registration (sign-up) | 10 requests | 3 minutes |
| POST /passwords (reset) | 10 requests | 3 minutes |

### Account Locking

After 5 failed login attempts, accounts are locked for 1 hour. Admin can unlock via:

```bash
rails users:unlock[email@example.com]
```

### Security Headers

Configured in `config/initializers/security_headers.rb`:

- `X-Frame-Options: SAMEORIGIN` — prevents clickjacking
- `X-Content-Type-Options: nosniff` — prevents MIME sniffing
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy` — disables camera, microphone, geolocation by default
- Content Security Policy via `content_security_policy.rb`

### Password Security

- 12-character minimum
- Pwned password check (Have I Been Pwned API)
- Password reset tokens are stateless (Rails 8.1 signed tokens, auto-expire)

### OAuth Security

- OAuth email matching requires a verified email authentication on the existing account
- Unverified accounts are not linked — a new user is created instead

### Activity Tracking

The `Trackable` concern logs all model changes to `ActivityLog`. Sensitive attributes are automatically stripped from metadata:

- `token`, `password_digest`, `password_reset_token`
- `verification_token`, `oauth_token`, `oauth_refresh_token`

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
