---
title: Email Flows
description: All transactional emails, their triggers, token expiry windows, and customization
keywords: email mailer authentication invitation magic link password reset verification token expiry smtp
---

# Email Flows

ModelRails sends transactional emails for authentication, invitations, and account management. All emails are delivered asynchronously via `deliver_later` (Solid Queue) and are fully internationalized.

## Mailers

| Mailer | Purpose |
|--------|---------|
| `AuthenticationMailer` | Email verification, password reset, email change |
| `InvitationMailer` | Workspace and project invitations |
| `MagicLinkMailer` | Passwordless sign-in and registration links |

## Email Reference

### Authentication Emails

| Email | Trigger | Recipient | Expiry |
|-------|---------|-----------|--------|
| Verification | New account registration | User's email | 24 hours |
| Password reset | "Forgot password" request | User's email | 2 hours |
| Email change verification | Email change initiated | New email address | 24 hours |
| Email change notification | Email change initiated | Current email address | N/A (informational) |

### Invitation Emails

| Email | Trigger | Recipient | Expiry |
|-------|---------|-----------|--------|
| Workspace invitation | Admin invites by email | Invitee's email | 7 days |
| Project invitation | Project member invites by email | Invitee's email | 7 days |

### Magic Link Emails

| Email | Trigger | Recipient | Expiry |
|-------|---------|-----------|--------|
| Sign-in link | Existing user requests passwordless sign-in | User's email | 15 minutes |
| Registration link | New email requests account creation | Entered email | 15 minutes |

## Token Security

All tokens are generated via `SecureRandom.urlsafe_base64(32)` (256 bits of entropy). Each token type has a fixed expiry window that cannot be extended — if a token expires, the user must request a new one.

Tokens are single-use: accepting an invitation, verifying an email, or resetting a password invalidates the token immediately.

## User Flows

### New User Registration

1. User submits registration form.
2. `Authentication` record created with a `verification_token`.
3. `AuthenticationMailer.verification_email` sent.
4. User clicks link → email marked as verified.
5. User can now sign in.

Verification can be resent from the profile page if the original email was lost.

### Password Reset

1. User clicks "Forgot password" on the sign-in page.
2. System generates a `password_reset_token` on the User record.
3. `AuthenticationMailer.password_reset_email` sent (2-hour expiry).
4. User clicks link → enters new password.
5. Token is invalidated on use.

### Passwordless Sign-In (Magic Links)

1. User enters their email on the sign-in page.
2. If the email exists: `MagicLinkMailer.sign_in_link` sent (15-minute expiry).
3. If the email is new: `MagicLinkMailer.registration_link` sent instead.
4. User clicks link → signed in (existing) or shown registration form (new).
5. The `MagicLinkCallbacksController` handles token validation and routing at click time.

### Email Change

1. User enters new email + current password in profile form.
2. `User#initiate_email_change!` generates a `pending_email_token`.
3. Verification sent to new email, notification sent to old email.
4. User clicks verification link → `User#confirm_email_change!` atomically swaps the address.
5. All linked OAuth authentication UIDs are updated to the new email.

### Invitation Acceptance

1. Admin creates invitation → `InvitationMailer.invite` sent.
2. Invitee clicks accept link.
3. If authenticated: invitation accepted immediately.
4. If not authenticated: redirected to sign-in/sign-up, then auto-accepted.
5. `Invitation#accept!` creates workspace membership (and project membership if applicable).

## Configuration

### From Address

`ApplicationMailer` resolves the from address in this order:

1. `Rails.application.credentials.dig(:mailer, :from)` — set this for production
2. `noreply@{default_url_options[:host]}` — automatic fallback
3. `noreply@example.com` — final fallback (makes it obvious setup is needed)

### SMTP Setup

Configure SMTP credentials in Rails encrypted credentials:

```yaml
# bin/rails credentials:edit
smtp:
  address: smtp.example.com
  port: 587
  user_name: your-user
  password: your-password
  authentication: plain
```

Then reference them in `config/environments/production.rb`:

```ruby
config.action_mailer.smtp_settings = {
  address: credentials.dig(:smtp, :address),
  port: credentials.dig(:smtp, :port),
  user_name: credentials.dig(:smtp, :user_name),
  password: credentials.dig(:smtp, :password),
  authentication: credentials.dig(:smtp, :authentication)
}
```

### Default URL Host

Set `config.action_mailer.default_url_options = { host: "yourapp.com" }` in each environment config. Email links use this to generate absolute URLs.

## Localization

All email subjects, greetings, body text, and button labels are defined in `config/locales/en/mailers.en.yml`. To translate emails, create locale files for your target language following the same key structure.
