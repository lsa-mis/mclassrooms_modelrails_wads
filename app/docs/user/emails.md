---
title: Email Flows
description: All transactional emails, their triggers, token expiry windows, and customization
keywords: email mailer authentication invitation magic link verification token expiry smtp
code:
  signup:
    - app/controllers/sessions/lookups_controller.rb
    - app/models/magic_link_token.rb
    - app/mailers/magic_link_mailer.rb
    - app/views/magic_link_mailer/
    - app/controllers/magic_link_callbacks_controller.rb
    - app/views/magic_link_callbacks/
---

# Email Flows

ModelRails sends transactional emails for authentication, invitations, and account management. All emails are delivered asynchronously via `deliver_later` (Solid Queue) and are fully internationalized.

## Mailers

| Mailer | Purpose |
|--------|---------|
| `AuthenticationMailer` | Email verification, email change, connected-account verification, sign-in collision alerts |
| `InvitationMailer` | Workspace invitations |
| `MagicLinkMailer` | Passwordless sign-in and registration links |
| `ReauthenticationMailer` | Confirmation codes for re-authenticating before a sensitive change |
| `NotificationMailer` | Notification emails and digests — see [Notifications](/docs/user/notifications) |

## Email Reference

### Authentication Emails

| Email | Trigger | Recipient | Expiry |
|-------|---------|-----------|--------|
| Verification | Requested from the verify-your-email page (an email sign-in starts unverified when a Google or GitHub account sets a password) | User's email | 24 hours |
| Email change verification | Email change initiated | New email address | 24 hours |
| Email change notification | Email change initiated | Current email address | N/A (informational) |
| Connected-account verification | Google or GitHub is connected, or used to sign up, with an address the provider hasn't proved for this account | The provider account's email | 24 hours |
| Sign-in collision alert | Someone signed in to another account tries to connect a Google or GitHub identity already linked to yours | Your email | N/A (informational) |
| Re-authentication code | You ask for an emailed code to confirm a sensitive change | User's email | 10 minutes |

### Invitation Emails

| Email | Trigger | Mailer action | Recipient | Expiry |
| ----- | ------- | ------------- | --------- | ------ |
| Workspace invitation | Admin invites a member by email | `InvitationMailer.with(invitation:).invite` | Invitee's email | 7 days |

### Magic Link Emails

| Email | Trigger | Recipient | Expiry |
|-------|---------|-----------|--------|
| Sign-in link | Existing user requests passwordless sign-in | User's email | 15 minutes |
| Registration link | New email requests account creation | Entered email | 15 minutes |

## Token Security

Invitation, magic-link and email-change tokens are generated via `SecureRandom.urlsafe_base64(32)` (256 bits of entropy); email-verification links carry a signed Rails token (`generates_token_for`) instead. Each token type has a fixed expiry window that cannot be extended — if a token expires, the user must request a new one.

Tokens are single-use: accepting an invitation, verifying an email, or resetting a password invalidates the token immediately.

## User Flows

### New User Registration (magic-link / passwordless-first)

1. User enters their email on the sign-in/sign-up page (`sessions#new`) and submits.
2. `Sessions::LookupsController#create` issues a `MagicLinkToken` and sends `MagicLinkMailer.registration_link` (new email) or `MagicLinkMailer.sign_in_link` (existing account).
3. User clicks the link (GET) → `MagicLinkCallbacksController#show` checks for an existing account. The GET never consumes the token or starts a session (a mail scanner or prefetcher can't burn the link):
   - Existing user: renders a "Sign in as x@y?" confirmation page; the button POSTs to the nested session (`POST /magic_link_callback/:token/session`), which consumes the token and starts the session.
   - New user: renders `magic_link_callbacks/new_registration` (name fields) for first-time signup.
4. New user submits their name → `MagicLinkCallbacksController#create` creates the User and a **verified** `Authentication` (email ownership proved by the link). No separate verification email is sent.
5. User is redirected to `after_authentication_url` (onboarding or home).
6. If the user is on the `:none` preset and has not yet completed onboarding, the `RequiresOnboarding` guard fires and redirects them into the onboarding wizard.

If the link doesn't arrive, **Didn't receive it? Try again** on the "check your email" screen lets the user request another.

### Passwordless Sign-In (Magic Links)

1. User enters their email on the sign-in page.
2. If the email exists: `MagicLinkMailer.sign_in_link` sent (15-minute expiry).
3. If the email is new and sign-up is open: `MagicLinkMailer.registration_link` sent instead. When sign-up is closed, nothing is sent, and the screen looks the same.
4. User clicks link (GET) → confirmation page ("Sign in as x@y?") whose button POSTs to sign in (existing), or the registration form (new). The GET never signs anyone in.
5. The `MagicLinkCallbacksController` handles token validation and routing; the token is consumed only on the POST.

### Forgot password / account recovery

There is no password-reset email. "Forgot password?" issues a **magic link** (a
`MagicLinkToken` carrying a `set_password` intent); clicking it signs the user in
and lands them on the change-password form. Magic link is the single
email-recovery primitive — see [Passkeys](/docs/developer/passkeys) for the passwordless
sign-in options and [Application Flows](/docs/developer/application-flows) for the journey.

### Email Change

1. User enters a new email in the profile form. Requesting the change requires recent **re-authentication** (a 15-minute window), not a password — so passwordless accounts can change their email too.
2. `User::EmailChange#initiate!(new_email)` generates a `pending_email_token`.
3. Verification sent to new email, notification sent to old email.
4. User clicks verification link → `User::EmailChange#confirm!` atomically swaps the address.
5. Nothing else needs updating: the email sign-in is keyed on the account, not the address, and Google or GitHub connections keep their provider's own IDs.

### Invitation Acceptance

1. Admin creates invitation → `InvitationMailer.with(invitation:).invite` sent (workspace member).
2. Invitee clicks accept link.
3. If authenticated: accepted immediately, provided the account's email matches the invited address.
4. If not authenticated: the token is stashed, the invitee registers, and the invitation is claimed when they verify the invited email — not at signup.
5. All paths go through `Invitation.consume!`, which enforces the email match (emailless magic-link invitations excepted) before `Invitation#accept!` creates the workspace membership.

## Configuration

### From Address

`ApplicationMailer` resolves the from address in this order:

1. `MAIL_FROM` in the environment
2. `Rails.application.credentials.dig(:mailer, :from)`
3. `noreply@` the mailer's default host (`RAILS_HOST`)

### SMTP Setup

For production, run `bin/mail-setup`, or set this by hand.

Where mail goes comes from the environment (`SMTP_ADDRESS`, `SMTP_PORT`,
`SMTP_DOMAIN`); the login lives in the per-environment credentials:

```yaml
# bin/rails credentials:edit --environment production
smtp:
  user_name: your-user
  password: your-password
```

`lib/mail_delivery.rb` builds `config.action_mailer.smtp_settings` from both,
and production refuses to boot when either is missing. Provider recipes:
[Deployment](/docs/developer/deployment#4-configure-outbound-mail).

### Default URL Host

Production reads `config.action_mailer.default_url_options` from `RAILS_HOST` (`config/environments/production.rb`); development and test use `localhost` (a Codespace, its forwarded host). Email links use this to generate absolute URLs.

## Localization

Email subjects, greetings, body text, and button labels live under each mailer's key in `config/locales/en/`: `mailers.en.yml` (authentication and re-authentication), `invitations.en.yml` and `clientside.en.yml` (invitations), `magic_links.en.yml`, and `notifications.en.yml`. To translate emails, create locale files for your target language following the same key structure.
