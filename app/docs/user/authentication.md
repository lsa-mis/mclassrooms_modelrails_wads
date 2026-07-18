---
title: Signing In
description: How to sign in and out of MiClassrooms with U-M single sign-on (Google or Okta)
keywords: sign in sign out sso single sign-on google okta weblogin u-m umich authentication account
---

# Signing In

MiClassrooms uses **U-M single sign-on**. You sign in with the same University
of Michigan account you already use everywhere else — there is no separate
MiClassrooms password to create or remember.

## Sign in with U-M Google or Okta

On the sign-in page you'll see two buttons:

- **Sign in with Google** — for U-M Google accounts on approved U-M domains.
- **Sign in with Okta** — for U-M Okta / Weblogin accounts.

Click either one, authenticate with U-M as you normally would, and you're in.
The **first** time you sign in, MiClassrooms creates your account automatically
from your U-M identity — there is no separate registration or email-verification
step. Which button your unit uses is up to how access is provisioned; both sign
you into the same MiClassrooms account.

## Who can sign in

Access follows your U-M identity:

- **Google** sign-in is limited to approved U-M email domains.
- **Okta** sign-in is gated by your U-M Okta organization membership.

Most U-M faculty, staff, and students can sign in and browse the classroom
directory as a **viewer**. Editing rooms, curating content, and administering the
directory are additional abilities granted by a MiClassrooms administrator — see
the [Administrator guide](/docs/admin/overview) for the roles.

## Signing out

Use the account menu (top right) to sign out. Sessions are not shared across
browsers or devices.

## Administrator break-glass sign-in

MiClassrooms is single-sign-on first, so the email/magic-link and passkey options
are hidden on the sign-in page in normal operation. A small number of
administrator accounts also have a password-based path as a **break-glass**
fallback — used, for example, when SSO is unavailable. If you're an administrator
who received a password-set link, you can set a password under **Settings** and
sign in by email; everyone else uses the Google or Okta buttons above.

---

**Related:** [Welcome](/docs/user/welcome) · [Finding a Room](/docs/user/finding-a-room) · [Notifications](/docs/user/notifications)
