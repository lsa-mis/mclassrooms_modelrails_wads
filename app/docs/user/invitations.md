---
title: Invitations
description: Receiving and accepting workspace invitations
keywords: invitation invite workspace accept decline block email-match magic link
---

## Receiving an invitation

When an admin invites you by email, you receive an invitation email with an **Accept** link and a **Decline** link. Invitations expire after 7 days; if yours has expired, ask the sender to resend it.

## Accepting an invitation

### If you already have an account

Click **Accept** in the email, sign in if prompted, and the invitation is accepted immediately. Your account's verified email must match the address the invitation was sent to.

### If you are new to the app

1. Click **Accept** in the email.
2. You will be prompted to sign in — enter the **same email address** the invitation was sent to and complete magic-link registration (you will receive a sign-in email).
3. The invitation is claimed once you verify the invited email address — not at the point of signup.

See [Authentication](/docs/user/authentication) for how magic-link sign-in works.

### Email-match guard

Emailed invitations are tied to a specific address. A leaked or forwarded invitation link **cannot be accepted from a different email address** — the guard rejects mismatches before the membership is created.

The one exception: **magic-link invitations** (a shareable URL that an admin copies and distributes, for example in a Slack channel) carry no email address and can be accepted by anyone with the link.

## Declining an invitation

Workspace invitations include a **Decline** link in the email. Clicking it marks the invitation as declined — no account or membership is created. (The "expiring soon" reminder is a different email and links only to **Accept** — decline from the original invitation email.)

Every invitation email also carries a **Don't invite me again** link. It opens a page that asks you to confirm; confirming declines the invitation and stops future invitations from that sender to your address. Only that link can do this: it exists in your email and nowhere else, which is how the app knows it is really you. Blocking is per-sender and per-address, and it needs no account. The decline page reminds you where the link is.

A block stops **delivery only**. It does not cancel or invalidate anything: an invitation link you already have still works while that invitation is valid, and blocking does not stop that person creating invitations or reaching you any other way.

Undoing a block is not self-serve yet — ask the people who run this app to lift it for you.

---

**Related:** [Workspaces](/docs/user/workspaces)
