---
title: Security
description: Security configuration, recommendations, and best practices for ModelRails
keywords: rate limiting account locking headers csp password oauth rack attack https bearer token libvips heic content types direct upload email normalization punycode recipient throttle nonce form-action provider registry
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

### Per-Recipient Email Throttle

The rate limits above gate how fast any one sender can trigger email sends.
They do not stop a **distributed flood by recipient**: N distinct senders — a
coordinated attack, or one attacker with N accounts — each send once, each
stays under its own per-sender limit, and the victim's inbox still receives N
emails.

`EmailRecipientThrottle` (`app/lib/email_recipient_throttle.rb`) closes that
gap by gating on the **recipient** address: at most 3 sends per recipient per
kind per hour by default. The policy lives in the module, not at call sites —
tighten or loosen it there. The counter lives in `Rails.cache` (Solid Cache),
keyed by SHA-256 of the canonical email plus the kind; buckets are independent
per kind, so a flood of one email type doesn't suppress legitimate sends of
another. The throttle is **fail-open**: if the cache backend can't increment,
the email is sent — delivery matters more than the throttle in a degraded
state.

One per-kind override (SEC-9): `:magic_link` allows 5 sends per 15 minutes,
shared by all four magic-link send endpoints (lookup sign-in, registration,
resend, password reset). They all mint into one intent-blind supersede pool,
so they must share one budget or endpoint-hopping resets it. The window
matches the 15-minute token expiry: a throttled-out user is never stranded
longer than their newest link's lifetime, and an attacker gets at most the cap
in supersedes per window before the victim's link becomes untouchable.

### Account Locking

After 5 failed login attempts, accounts are locked for 1 hour. Auto-unlock occurs after the lockout period.

**Scope — password sign-in only, by design.** The failed-attempt counter and
the `locked?` gate live in the password path (`sessions#create`). Passkey and
magic-link sign-in do **not** check the lock: neither factor is brute-forceable
the way a password is (a passkey is a cryptographic assertion; a magic link
requires control of the inbox), so locking them out would punish exactly the
factors a locked-out user needs to get back in. Consequence to be aware of:
a locked account is locked out of *passwords*, not out of the account — the
owner can still sign in with a passkey or magic link. If your fork wants a
lock to mean "no sign-in at all", add the `locked?` check to
`magic_link_callbacks#sign_in` and `Passkeys::AuthenticateCeremony` as well.

Admin rake tasks:

```bash
rails users:unlock[email@example.com]     # Unlock a locked account
rails users:verify[email@example.com]     # Manually verify an email
rails users:suspend[email@example.com]    # Suspend an account (destroys sessions, deactivates memberships)
```

### Session Lifetime

Sessions expire — a signed-in session is not valid forever. `Session#expired?`
enforces two limits, both tunable in `config/initializers/sessions.rb`:

- **idle timeout** (default 30 days) — no activity for this long signs you out
- **absolute timeout** (default 90 days) — this long after sign-in regardless of activity

Expiry is enforced fail-closed in `Authenticatable#find_session_by_cookie`
(an expired session resolves to `nil`, so the sweeper is housekeeping, not a
security control), and the signed cookie carries a matching `expires:`.
`last_active_at` is refreshed through an in-memory throttle so the write stays
off the SQLite single-writer hot path. Changing or removing a password signs
out every *other* session; users can review and revoke devices at
`/settings/sessions`. `ExpiredSessionsSweepJob` deletes expired rows daily.

### Re-Authentication (Sensitive Changes)

Actions that add, remove, or change an authentication factor require a recent
proof of identity, so a borrowed session can't be turned into a takeover.
`Reauthenticatable#require_reauthentication!` gates: password change/removal,
passkey enrollment and deletion, email change, and OAuth unlink. It checks
`Session#reauthenticated?` (a 15-minute window on `reauthenticated_at`, set at
sign-in and refreshed by the interstitial) and, if stale, sends the user to
`/settings/reauthentication`.

The interstitial offers only the factors the user has (`User#available_reauth_factors`):
password, a passkey (verified through `AuthenticateCeremony` **bound to the
current user** — another account's passkey is rejected), or a one-time
`ReauthenticationChallenge` code emailed and entered in-page (never a link, so
it can't be replayed into a sign-in). All of it is tunable in
`config/initializers/sessions.rb`; `reauth_enabled = false` makes the gate a
no-op — except passkey enrollment, which stays gated regardless: enrollment
mints a durable, phishing-resistant credential and revokes nothing, so it is
hard-wired (`require_reauthentication!(force: true)`) and additionally fires
`PasskeyAddedNotifier`. Email changes are gated here rather than on a
password, so passwordless users can change their email.

Sign-ins from an unrecognized browser/OS additionally trigger a security
notification (`SignInFromNewDeviceNotifier`). The alert is gated by
`new_device_notification` in the same initializer; device fingerprints are
recorded regardless, so turning the alert back on later keeps full history.

### Magic-Link Tokens

The bearer token is stored only as a SHA256 digest (`MagicLinkToken.token_digest`);
the plaintext lives solely in the emailed URL, so a leaked table can't be used
to sign in. 256 bits of entropy means a plain unsalted digest is sufficient —
contrast the 6-digit `ReauthenticationChallenge`, which needs a pepper + rate
limit. Clicking a magic link is a two-step GET→POST: the GET renders a
"Sign in as x@y?" confirmation and never consumes the token or starts a session,
so a mail scanner or prefetcher doing a bare GET can't burn the link; the POST
(the visible button) runs the atomic consume and signs in. Mirrors the join-link
confirmation flow.

### Security Headers

Configured in `config/initializers/security_headers.rb`:

- `X-Frame-Options: SAMEORIGIN` — prevents clickjacking
- `X-Content-Type-Options: nosniff` — prevents MIME sniffing
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy` — disables camera, microphone, geolocation by default
- Content Security Policy via `content_security_policy.rb` (enforced in development, production, and test — see #499/#120 in `CHANGELOG.md` for why test enforcement matters); its decided trade-offs are documented in the next section

### Content Security Policy

The CSP lives in `config/initializers/content_security_policy.rb`. Three of
its choices are decided trade-offs, not defaults waiting to be "fixed":

**`style-src` carries `unsafe-inline` (#444).** Tailwind 4 injects inline
`style` attributes and Turbo writes inline styles during morphs and
transitions, so a nonce/hash regime for styles breaks rendering in ways that
resurface with every framework update — a permanent breakage tax. The accepted
risk is narrow: style-only injection, with no script execution path
(`script-src` stays `'self'` plus a nonce). Revisit only if Tailwind and Turbo
ship nonce-compatible styling, not before.

**The script nonce is per-session, not per-request (#443).** The nonce
generator returns the session id, so one nonce is valid for a session's
lifetime. That lets Turbo cache and restore pages whose inline bootstrap still
validates — a per-request nonce invalidates every cached page's scripts on
restore. Cost accepted: a nonce leaked from one response is valid for the rest
of that session, a marginal loss since the session cookie it derives from is
the larger secret. Revisit only with a concrete injection vector that a
per-request nonce would have stopped. One subtlety: a visitor's *first*
request has no session yet, so the generator falls back to a random nonce —
emitting the invalid blank `'nonce-'` would be ignored by browsers, blocking
every inline script (the importmap bootstrap and `import "application"`) and
leaving Stimulus never booting for first-time visitors. Nonces apply to
`script-src` only.

**`form-action` is derived from the OAuth provider registry.** CSP evaluates
the entire redirect chain: the POST to `/auth/:provider` returns a 302 to the
provider's consent page, and browsers block that step unless the provider host
is in `form-action` — **silently**: no server error, nothing in the logs,
"clicking Sign in with SSO does nothing." The directive is built from
`config.x.oauth_providers` (#312) so a swapped provider can never be forgotten
here; `fetch` raises at boot on a registry entry without a `form_action_host`.
See [OAuth Security](#oauth-security) for the registry itself.

### Password Security

- 12-character minimum
- Pwned password check (Have I Been Pwned API)
- Account recovery issues a single-use `MagicLinkToken` (`set_password` intent, 15-minute expiry), not a stateless reset token

### Canonical Email Keys

`User#email_address` (and `pending_email`) are normalized through
`EmailNormalizer` (`app/lib/email_normalizer.rb`): Unicode-NFC-normalized,
stripped, downcased, with the **domain** punycode-encoded. Every email
comparison in the app — the invitation `EmailMismatch` guard, OAuth email
matching, email change — goes through `EmailNormalizer.equivalent?`, so
storage and lookup share a single canonical key.

Why NFC: visually identical strings can have different byte sequences
depending on Unicode form — "é" can be the single codepoint U+00E9 (NFC) or
"e" plus combining acute U+0301 (NFD). User input via web forms tends to be
NFC and OAuth providers usually return NFC, but rows imported from other
systems or copy-pasted from PDFs may be NFD. Without normalizing both sides,
the same mailbox can exist as two `User` rows (a duplicate account), or an
invitation or OAuth lookup can miss the account it should have matched.

Why punycode the domain: DNS only speaks ASCII, so an IDN like
`user@bücher.de` is encoded as `user@xn--bcher-kva.de` by mail servers. A user
might paste either form into a web form, but they are the same address —
normalizing to the ASCII (punycode) form gives both representations one
canonical key. The **local part** is deliberately untouched: SMTPUTF8
(RFC 6531) lets mailboxes accept Unicode local parts, and IDNA does not apply
there.

### OAuth Security

- OAuth email matching requires a verified email authentication on the existing account
- Unverified accounts are not linked — a new user is created instead

**Provider registry.** `config/initializers/0_oauth_provider_registry.rb` is
the single home for OAuth provider knowledge (#312). Three consumers derive
from it rather than repeating it: the CSP builds `form-action` from each
entry's `form_action_host` (see [Content Security Policy](#content-security-policy)
above), `config/initializers/omniauth.rb` declares strategies for the
registry's keys, and `app/helpers/oauth_helper.rb` renders sign-in buttons
from `name`/`icon`. Duplicated knowledge does not announce its drift; it just
waits — centralizing the registry means a swapped provider can't be updated in
one place and forgotten in another. Two mechanics worth knowing: the `0_`
filename prefix makes the initializer sort before its consumers (initializers
run in filename order), and the registry lives on `config.x` because app
constants are not referenceable at initializer time (Zeitwerk). To add or swap
a provider: add the entry here (`form_action_host` is the consent-screen
origin the browser is redirected to), declare the strategy in `omniauth.rb`,
and update the literal cross-check hash in
`spec/initializers/content_security_policy_spec.rb` — the spec fails loudly
until you do, which is the point: double-entry bookkeeping on a
security-relevant value.

### Activity Tracking

The `Trackable` concern logs all model changes to `ActivityLog`. Sensitive attributes are automatically stripped from metadata:

- `token`, `password_digest`
- `oauth_token`, `oauth_refresh_token`

### Image Processing (Active Storage + libvips)

Active Storage processes variants with libvips (`variant_processor = :vips`, the Rails 8.1 default). Since Rails 8.1.3.1 it calls `Vips.block_untrusted(true)` while booting, disabling the loaders and savers libvips flags as unsafe for untrusted input. That is what closes CVE-2026-66066, where a crafted upload could be used to read arbitrary files from the server — including the process environment, and therefore `secret_key_base`.

Two consequences to know about:

- **libvips 8.13+ and ruby-vips 2.2.1+ are required.** Below either, Active Storage raises at boot rather than run unsecured. The production image, the devcontainer and CI all satisfy this; check your own if you build a custom image.
- **BMP, ICO and PSD variants raise `Vips::Error`.** `config/initializers/active_storage.rb` subtracts exactly those three (`image/bmp`, `image/vnd.microsoft.icon`, `image/vnd.adobe.photoshop`) from `variable_content_types`, which makes `Blob#representable?` false, so the blob partial renders its file-chip branch instead. Without the subtraction they render an `<img>` whose representation URL 500s when the browser fetches it — Action Text attachments carry no content-type allowlist and processing is lazy, so the page still returns 200 and the failure shows up as a broken image plus a logged 500 on every view. The subtraction is exact by verification, not guesswork: on libvips 8.18.4 under `Vips.block_untrusted(true)`, every other entry in the default list (PNG, JPEG, GIF, WebP, TIFF, AVIF, HEIC, HEIF) still loads and transforms — nothing else may be removed there. A fork that needs one of the three should re-enable the specific libvips operation rather than living with the file chip.

The initializer governs what renders as a *variant*. What can be *uploaded* is gated per surface — avatar/logo attachments by model validations, rich-text direct uploads by `DirectUploadsController` (next section). Widen those, not the initializer.

Uploads backing user avatars, workspace logos and project logos are restricted by model validations to `ApplicationRecord::IMAGE_CONTENT_TYPES` (PNG, JPEG, GIF, WebP, HEIC, HEIF) with size caps. That list is deliberately **wider** than `ActiveStorage.web_image_content_types`, which is the set a browser renders directly: Rails converts a variant of anything outside that set to PNG automatically, so the constraint that matters is "can libvips process it safely", not "can a browser display it". HEIC/HEIF is the iPhone camera default — excluding it would bounce the single most common source of an avatar or logo upload for no security benefit: both types load and transform under `Vips.block_untrusted(true)` and remain in `variable_content_types`, and the production base image (Debian's libvips 8.16.1 in `ruby:slim`) ships `heifload` and `heifsave`. The list is one shared constant rather than a copy per model because a single list guards four attachments across two models — a copy per call site is how #496's drift happened.

### Rich-Text Direct Uploads (SEC-7)

Rich-text (Action Text) attachments upload through `DirectUploadsController`, which shadows the Active Storage engine's direct-upload endpoint. The engine's own controller is **unauthenticated** — it inherits `ActionController::Base`, not the app's `ApplicationController` — and mints signed storage-write URLs from client-declared metadata with no type or size gate. The shadow inherits `ApplicationController` (bringing `Authenticatable`, `Current`, and the global `rescue_from`s along for free): it requires a signed-in session, rate-limits per user, and enforces an allowlist (`IMAGE_CONTENT_TYPES` + PDF) and a 10 MB cap. Both knobs are constants on that controller and are THE place a fork widens or narrows rich-text uploads; Office formats stay out by default because they are a real parser surface.

Enforcement reality — what each check actually buys (panel, 2026-08-13):

- The declared **byte size is a hard ceiling**: it is baked into the signed token, and the disk service re-verifies content length + checksum on receipt, so the cap bounds the bytes that reach disk.
- The declared **content type filters honest clients only**: Active Storage re-identifies the real type from the stored bytes at attach time, where model validations judge it.
- **Attachment happens by signed GID** embedded in the submitted body — a blob's `attachable_sgid` is sufficient to attach it — so any *new* blob-creation path a fork adds must carry its own gate.

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
