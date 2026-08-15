---
title: Account Management
description: Profile editing, email changes, passwords, avatars, themes, and connected accounts
keywords: account profile email password avatar theme preferences connected accounts oauth gravatar initials crop
---

# Account Management

All account features live under the `/account` namespace and require authentication.

## Profile Editing

**Route:** `PATCH /account/profile`

Update your first name and last name. Both fields have a 100-character maximum.

## Changing Your Email

Email changes use a **two-email verification flow** to prevent account hijacking:

1. Enter a new email address in the profile form. Requesting the change requires recent **re-authentication** (see below) rather than a password, so passwordless accounts can change their email too.
2. A **verification link** is sent to the *new* address (expires in 24 hours).
3. A **notification email** is sent to the *old* address so you know a change was requested.
4. Click the verification link to confirm. The old email is replaced atomically.

You can cancel a pending email change from the profile page at any time. If the token expires, simply request the change again.

**Model method:** `Users::EmailChange#initiate!(new_email)` sets the pending fields; the controller dispatches both mailers.

## Passwords

### Setting a Password (OAuth-only accounts)

If you signed up via Google or GitHub and have no password yet, visit `/settings/password/new` to add one. This creates an email-based Authentication record so you can also sign in with email and password.

### Password Requirements

- Minimum 12 characters
- Cannot appear in the [Have I Been Pwned](https://haveibeenpwned.com/Passwords) breach database
- Confirmation required

### Password Reset

Request a reset from the sign-in page ("Forgot password?"). If the account has a password set, a **single-use magic-link** (**15-minute expiry**) is sent; clicking it proves email ownership and lands on the password-change form — no current password needed. Passwordless accounts have nothing to reset and simply sign in with a magic link instead.

## Re-authentication for Sensitive Changes

Some account changes ask you to confirm it's really you before they go through, so a borrowed session can't be turned into a lasting takeover. This applies when you:

- change or remove your password
- add or delete a passkey
- change your email address
- disconnect a Google or GitHub account

You confirm with whatever you have — your password, a passkey, or a one-time code emailed to you and entered on the page. The confirmation lasts about 15 minutes, so a burst of changes only prompts you once.

## Avatar / Profile Photo

**Routes:**

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/account/avatar/hub` | Identity picker modal content |
| PATCH | `/account/avatar` | Upload or change avatar |
| DELETE | `/account/avatar` | Remove photo, revert to initials |

### Avatar Sources

The identity picker modal lets you choose between:

- **Upload** — crop a photo with the built-in cropper (PNG, JPEG, GIF, WebP; max 5 MB)
- **Gravatar** — automatically fetched from your email hash (shown only if a Gravatar exists)
- **Initials** — generated from your first and last name with a customizable hue color

### How Upload Works

1. Select or drag an image file.
2. The cropper opens with a 1:1 aspect ratio overlay.
3. Adjust zoom and position, then save.
4. Two attachments are stored: `avatar` (cropped) and `avatar_original` (full image for re-cropping).
5. Crop coordinates are preserved in the original's blob metadata.

### Color Picker

Each avatar source displays with a background hue. Use the inline color picker to adjust `primary_color` (an integer 0–360 representing the OKLCH hue). This color is used for initials backgrounds and branding accents.

## Theme Preferences

**Route:** `PATCH /account/theme_preference`

Cycle through three modes: **Light**, **Dark**, **System** (follows OS preference). The choice is:

- Persisted in a cookie for immediate application (no flash of wrong theme)
- Saved to `UserPreferences.theme` in the database for cross-device consistency

The theme toggle in the header cycles through all three modes on click.

## Connected Accounts

**Routes:**

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/account/connected_accounts` | List all auth methods |
| DELETE | `/account/connected_accounts/:id` | Disconnect a provider |

View all authentication methods linked to your account (email/password, Google, GitHub). You can disconnect any provider **except the last one** — at least one authentication method must remain.

### Linking a New Provider

Sign in to your existing account, then visit the OAuth provider's sign-in button. If the email matches your account, the provider is linked automatically. If the email doesn't match, a new account would be created instead.

## Authorization

All account controllers use Pundit policies scoped to the current user. You can only edit your own account — there is no admin override for account settings.
