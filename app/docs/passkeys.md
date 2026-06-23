---
title: Passkeys
description: Configure WebAuthn passkeys, set up local HTTPS testing, manage credentials in Settings, and troubleshoot common issues
keywords: passkeys webauthn fido2 authentication biometric rp-id origin secure context https local testing settings credentials
---

# Passkeys

Passkeys let users sign in with their device's built-in authenticator — fingerprint, face, or PIN — instead of a password or magic link. The credential never leaves the device, so phishing is structurally impossible.

**Magic link remains the universal fallback.** Every user can always sign in via email magic link regardless of passkey status. No user is ever stranded: if a device is lost or passkeys are unavailable, magic link works.

## How it works

Registration creates a public/private key pair on the device and stores the public key server-side as a `WebauthnCredential`. Authentication verifies a signed challenge against that public key. A monotonic sign count is advanced on every successful authentication; a regression is treated as a possible cloned authenticator and the sign-in is rejected.

Passkeys use the [WebAuthn Level 2](https://www.w3.org/TR/webauthn-2/) standard via the `webauthn` gem.

## Relying Party (RP) configuration

WebAuthn binds each credential to a **relying party ID** (RP ID) — the effective domain — and an **origin** (scheme + host + port). The browser enforces this binding: a credential registered on `app.example.com` cannot be used on `staging.example.com` or `example.com`.

### Default derivation

The RP ID and origin are derived automatically from the app host configured for Action Mailer (`config.action_mailer.default_url_options[:host]`). On `localhost`/`127.0.0.1` the scheme defaults to `http`; on any other host it defaults to `https`.

### Environment variable overrides

Override the defaults by setting environment variables:

| Variable | Purpose | Example |
|---|---|---|
| `WEBAUTHN_ORIGIN` | Full origin URL. Drives the RP ID when `WEBAUTHN_RP_ID` is not set. | `https://app.example.com` |
| `WEBAUTHN_RP_ID` | RP ID only (the domain). Overrides the value derived from origin. | `example.com` |

`WEBAUTHN_RP_ID` is rarely needed; set it only when the RP ID must differ from the origin's host (for example, a shared parent domain across subdomains).

### Per-environment guidance

**Production** — no extra variables needed if `action_mailer.default_url_options[:host]` already matches your public domain. Set `WEBAUTHN_ORIGIN` explicitly if any ambiguity exists or if you serve from a non-standard port.

**Staging / preview** — set `WEBAUTHN_ORIGIN=https://staging.example.com`. Because passkeys are domain-bound, staging and production credentials are always separate; there is no cross-environment leakage.

**Development** — see [Local HTTPS testing](#local-https-testing) below.

### Domain-change caveat

Passkeys are cryptographically bound to the RP ID at registration time. If you rename or migrate to a new domain, **all existing passkeys stop working** — the browser will reject the credential for the new domain. Users are not locked out: magic link continues to work. After signing in via magic link users can register a new passkey for the new domain under Settings → Passkeys.

Plan domain changes accordingly: announce to users, allow a re-registration window, and consider keeping the old domain active long enough for users to transition.

## Local HTTPS testing

WebAuthn requires a **secure context** (`window.isSecureContext === true`). The sign-in UI detects this at page load: if the context is not secure, the passkey button is hidden and magic link is shown instead, so the rest of the app continues to work.

`localhost` and `127.0.0.1` are treated as secure contexts by most browsers, so plain `http://localhost:3000` works for passkey testing in Chrome and Firefox. Safari requires an actual HTTPS origin.

For full cross-browser local testing, use one of:

- **Rails SSL server** — `bin/rails s --ssl` (generates a self-signed certificate; add it to your OS trust store once)
- **Local tunnel** — ngrok or Cloudflare Tunnel: set `WEBAUTHN_ORIGIN=https://<tunnel-host>` before starting the server

Always set `WEBAUTHN_ORIGIN` to match the exact origin the browser sees:

```bash
WEBAUTHN_ORIGIN=https://localhost:3000 bin/rails s --ssl
```

## Managing passkeys

Users manage their passkeys at **Settings → Passkeys** (`/settings/passkeys`).

- **List** — all registered passkeys are shown with their nickname and registration date.
- **Add** — triggers the browser's native passkey enrollment flow; the optional nickname (e.g. "My MacBook") is stored for identification.
- **Remove** — soft-deletes the credential (discard). The passkey is immediately unusable for authentication. Because multiple passkeys can be registered, removing one does not affect others. Magic link always remains available.

After a user's first successful magic-link sign-in (while they have no passkey yet), a one-time, non-blocking banner suggests adding one. It links to **Settings → Passkeys**; dismissing it (×) — or registering a passkey — stamps `passkey_prompt_seen_at` so it never reappears. The banner hides on browsers without WebAuthn support.

**Writing passkey tests?** See the contributor harness notes in [QA flows](/docs/qa-flows).

## Browser support

Passkeys (WebAuthn with discoverable credentials) are supported in:

- Chrome 108+ / Edge 108+
- Safari 16+ (macOS Ventura, iOS 16)
- Firefox 122+ (platform authenticators; cross-device via USB/NFC/BLE)

Older browsers and environments where `window.isSecureContext` is false fall back to magic link automatically — no configuration needed.

## Troubleshooting

| Symptom | Likely cause | Resolution |
|---|---|---|
| "Passkey verification failed" at sign-in | RP ID or origin mismatch between registration and authentication | Verify `WEBAUTHN_ORIGIN` matches the browser's address bar origin exactly (scheme, host, port) |
| "The passkey challenge has expired or was already used" | Challenge consumed or session timed out (challenges expire after a short window) | Try again; if persistent, check server clock skew |
| "No passkey found for this device" | Credential registered on a different domain, or on a different device without sync | Sign in via magic link; re-register a passkey for this device/domain |
| "This passkey is already registered to your account" | Same authenticator registered twice | Expected behavior — the existing registration is reused; no action needed |
| "Passkey verification failed: possible cloned authenticator" | Sign count regressed, suggesting credential duplication | Remove the affected passkey from Settings and re-register; if persistent, treat as a security event |
| Passkey button is missing entirely | Browser does not support WebAuthn, or page is served over HTTP (not a secure context) | Use magic link; for local dev, switch to HTTPS or use `localhost` |
| Sign-in button does nothing | Browser platform authenticator not set up (no fingerprint/PIN enrolled) | Set up device biometrics or PIN in OS settings |
| Passkeys do not appear after a domain change | Credentials are bound to the old RP ID | Sign in via magic link and re-register under the new domain |
