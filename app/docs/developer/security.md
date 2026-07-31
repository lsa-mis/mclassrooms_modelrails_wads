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
- Content Security Policy via `content_security_policy.rb` (enforced in development, production, and test — see #499/#120 in `CHANGELOG.md` for why test enforcement matters)

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

### Image Processing (Active Storage + libvips)

Active Storage processes variants with libvips (`variant_processor = :vips`, the Rails 8.1 default). Since Rails 8.1.3.1 it calls `Vips.block_untrusted(true)` while booting, disabling the loaders and savers libvips flags as unsafe for untrusted input. That is what closes CVE-2026-66066, where a crafted upload could be used to read arbitrary files from the server — including the process environment, and therefore `secret_key_base`.

Two consequences to know about:

- **libvips 8.13+ and ruby-vips 2.2.1+ are required.** Below either, Active Storage raises at boot rather than run unsecured. The production image, the devcontainer and CI all satisfy this; check your own if you build a custom image.
- **BMP, ICO and PSD variants raise `Vips::Error`.** `config/initializers/active_storage.rb` removes those three from `variable_content_types`, so attachments of those types render as a file chip. Without it they render an `<img>` whose representation URL 500s when the browser fetches it — processing is lazy, so the page still returns 200 and the failure shows up as a broken image plus a logged 500 on every view. PNG, JPEG, GIF, WebP, TIFF, AVIF, HEIC and HEIF are unaffected.

Uploads backing user avatars and workspace logos are additionally restricted to `image/png`, `image/jpeg`, `image/gif` and `image/webp` by model validations. Action Text attachments are not restricted — if your fork needs an allowlist there, add one rather than relying on the variant layer to refuse the file.

The `>= x.y.z` floor on the `rails` gem in the Gemfile is a security floor: it stops a fresh `bundle install` in a fork from resolving back onto a version patched for a known CVE. Dependabot rewrites that line on every Rails bump and will drop the floor, so `spec/code_smells/template_invariants_spec.rb` fails if the requirement ever admits a vulnerable release again.

## External Client Access

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

### Responding to a Secret Exposure

Some vulnerabilities disclose anything readable by the app process — CVE-2026-66066 above is one. Upgrading closes the hole but does not undo an exfiltration that already happened. If your deployment ran an affected version while reachable by untrusted users, treat every secret the process could read as exposed and replace it:

1. `secret_key_base` — rotating it signs out every user and invalidates encrypted and signed cookies, signed global IDs, and existing Active Storage URLs.
2. The master key (`config/master.key` or `RAILS_MASTER_KEY`) and everything `config/credentials.yml.enc` decrypts. Re-encrypt under the new key with `bin/rails credentials:edit`.
3. Storage service credentials (S3, GCS, Azure) if you moved off the local disk service.
4. Database credentials, if your database is not the bundled SQLite file.
5. API tokens and keys for every third-party service the app calls — OAuth client secrets, mail provider keys, error reporting DSNs.

Replace secrets outright. Keeping the old value as a rotation fallback is only an intermediate step; do not leave an exposed secret in the rotation list.
