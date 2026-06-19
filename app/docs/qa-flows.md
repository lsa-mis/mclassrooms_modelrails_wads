---
title: "QA: User Flow Walkthroughs"
description: Manual verification guide for the five core user-facing flows — signup, magic-link, OAuth, workspace join, and identity surfaces. Each section lists the config required, a numbered walkthrough, and edge cases.
keywords: qa testing signup invitation magic-link oauth workspace join identity verification manual walkthrough
audience: [guide, technical]
---

# QA: User Flow Walkthroughs

Use this guide to verify the app manually after initial setup or after a config change. Each section covers exactly one user-facing flow: the environment variables to set, a numbered walkthrough with expected outcomes, and the edge cases worth exercising.

## Before you start

**Email capture.** In development every outbound email is intercepted by Letter Opener. Navigate to [`/letter_opener`](/letter_opener) in a separate tab — keep it open and click **Refresh** after any action that sends email. You do not need a real email account for any of these flows.

**Console and seed.** When `SIGNUP_MODE=invite_only` you need an owner account before you can invite others. Create one with:

```bash
bin/rails console
User.create!(email_address: "owner@example.com", first_name: "Test", last_name: "Owner", password: "SecureP@ssw0rd123!")
```

Or run `bin/rails db:seed` if you configured the shared-preset seed variables.

**Config lives in `.env`.** All environment variables below are read at boot time. After changing `.env`, restart `bin/dev` for the change to take effect. The valid values for each variable are documented in `.env.example`; the app raises on an unrecognized value at startup.

**Private/incognito windows.** Several flows require acting as a different user simultaneously. Use a private window so the two sessions do not share cookies.

---

## Config reference

| Variable | Where set | Values | What it controls |
|---|---|---|---|
| `SIGNUP_MODE` | `.env` | `open` · `invite_only` | Whether `/registrations/new` is publicly accessible. Default: `invite_only`. |
| `WORKSPACE_ON_SIGNUP` | `.env` | `personal` · `shared` · `none` | Which workspace (if any) a new user lands in after signup. Default: `personal`. |
| `SIGNUP_PERMITTED_JOIN_STRATEGIES` | `.env` | `invite` · `invite,open_link` | Instance ceiling on join methods. `open_link` must appear here before any workspace can enable shareable join links. Default: `invite`. |
| `TENANCY_WORKSPACE_CREATION` | `.env` | `enabled` · `disabled` | Whether the "New workspace" route and UI are available to signed-in users. Default: `enabled`. |
| OAuth credentials | `bin/rails credentials:edit --environment development` | — | Google and GitHub client ID / secret. Without these, OAuth buttons redirect to the sign-in page with an error. |

---

## Flow 1 — Signup and invitations

### 1a. Open signup (`SIGNUP_MODE=open`)

**Config:** set `SIGNUP_MODE=open` in `.env` and restart `bin/dev`.

1. In a private window navigate to `/registrations/new`.
   **Expect:** A registration form with fields for email, first name, last name, password, and password confirmation.
2. Fill in all fields and submit.
   **Expect:** You are signed in immediately and redirected (the app calls `start_new_session_for` before redirecting). A verification email is sent to your address — check `/letter_opener`.
3. At this point your email is **unverified**. The account is fully functional, but any pending invitation or open-link join you arrived with (stashed in the session cookie) will not be claimed until you click the verification link in that email.
4. Open the verification email in `/letter_opener` and click the link.
   **Expect:** You land on `settings/connected_accounts` (or `root_path` if you were not signed in) with a success notice. From this point the email authentication is verified.

**What `SIGNUP_MODE=open` does not change.** The registration form is always available to visitors who arrive with a valid `session[:pending_invitation_token]` or `session[:pending_join_token]` — even under `invite_only`. This is by design: an invitation or join-link is what opens the gate.

### 1b. Invite-only signup (`SIGNUP_MODE=invite_only`)

**Config:** set `SIGNUP_MODE=invite_only` in `.env` and restart `bin/dev`.

1. In a private window navigate to `/registrations/new` with **no invitation**.
   **Expect:** The closed page (`registrations/closed.html.erb`) renders — a heading, a body paragraph, and a link to sign in. **Not a 404.** The response is a 200 with the `:closed` template.
2. Check that OAuth buttons on the closed page redirect to `/registrations/new` with an alert rather than proceeding — this is the `signups_open?` guard in the OAuth callback.

### 1c. Invite flow (owner sends, recipient accepts)

**Config:** `SIGNUP_MODE=invite_only` is fine; the invitation itself opens the gate.

1. Sign in as an owner of a workspace.
2. Navigate to the workspace's invitations: `/workspaces/:slug/invitations/new`.
   Fill in the recipient's email address and submit.
   **Expect:** The invitation is created and an invitation email is dispatched — check `/letter_opener`.
3. Open the invitation email in `/letter_opener`. Click **Accept invitation**.
   The link is `GET /invitations/:token/accept`.
   **Expect (unauthenticated browser):** The accept page (`invitation_accepts#show`) renders. The token is stashed in `session[:pending_invitation_token]`. A "Register or sign in to accept" prompt is shown.
4. From the same browser, navigate to `/registrations/new`.
   **Expect:** The registration form renders (the session token satisfies `signups_open?`).
5. Register with the **same email address** that the invitation was addressed to.
   **Expect:** You are signed in immediately. The invitation token is persisted on the new email `Authentication` (not consumed yet). A verification email is dispatched — check `/letter_opener`.
6. Click the verification link in `/letter_opener`.
   **Expect:** `Settings::ConnectedAccountsController#verify` verifies the authentication and then calls `auth.claim_pending_invitation!` which calls `Invitation.consume!` with an email-match guard. Because your proven email matches the invitation address, the invitation is accepted and you are added to the workspace. You are redirected to `root_path` with a success notice.

**Signed-in accept (POST path).** If the recipient is already signed in when they click the accept link:
`POST /invitations/:token/accept` calls `Invitation.consume!` immediately (no deferred email-match check needed — the signed-in user's proven email is used). If the signed-in email does not match the invitation email, `Invitation::EmailMismatch` is rescued and a mismatch alert is shown; you are redirected to `root_path`.

### Edge cases — Invitations

- **Single-use.** After a successful claim, clicking the same accept link again shows an "expired or used" alert and redirects to `root_path`.
- **Expired invitation.** Invitations expire after **7 days** (set at creation: `expires_at: 7.days.from_now`). Attempting to accept an expired invitation shows the same "expired or used" alert.
- **Email-bound.** An invitation addressed to `alice@example.com` cannot be claimed by a signed-in user whose email is `bob@example.com` — `Invitation::EmailMismatch` is raised and the flow aborts with an alert.
- **Race (already consumed).** If two requests attempt to accept the same invitation simultaneously, `Invitation#accept!` acquires a lock; the loser raises `NotAcceptable`.

---

## Flow 2 — Magic-link sign-in

**Config:** No special config required. Works under any `SIGNUP_MODE`.

### Existing user (passwordless)

1. Navigate to `/session/new` (the sign-in page).
2. Enter an email address that belongs to an existing user without a password and click **Continue**.
   The form submits to `POST /session/lookup`.
   **Expect:** The `check_email` page renders inline (Turbo Frame replaces the form). In development the heading is a link to `/letter_opener`.
3. Open `/letter_opener` and click the magic-link sign-in email.
   The link is `GET /magic_link_callback/:token`.
   **Expect:** `MagicLinkCallbacksController#show` finds the user, atomically consumes the token (prevents double-spend), calls `start_new_session_for`, and redirects to `after_authentication_url`.
4. The token is now consumed. Clicking the same link a second time shows an invalid-token alert.

### Existing user (has password)

1. Navigate to `/session/new` and enter the email address.
   **Expect:** The password form renders inline (not the `check_email` page) — the lookup path checks `user.has_password?` and renders `:password_form` instead.

### Unknown email (new user)

1. Navigate to `/session/new` and enter an email address that has **no account**.
   **Expect:** The `check_email` page renders (same as passwordless — no user-enumeration difference). A registration magic-link email is dispatched to that address — check `/letter_opener`.
2. Click the link in `/letter_opener`.
   **Expect:** `MagicLinkCallbacksController#show` finds no user for that email. It renders the `:new_registration` view — a name-only form (no password field) with the email pre-filled.
3. Fill in first and last name and submit.
   **Expect:** A user is created with the email already verified (`verified_at: Time.current` is set on the email authentication inside the transaction — no separate verification email). You are signed in and redirected.
4. If `SIGNUP_MODE=invite_only` and no pending session token, the `create` action refuses and redirects to `/registrations/new` with an alert before creating any user.

### Edge cases — Magic link

- **15-minute expiry.** The token is valid for exactly 15 minutes (`expires_at: 15.minutes.from_now`). An expired link shows the invalid-token alert.
- **One-time use.** `MagicLinkToken.consume!` does a compare-and-swap; a second concurrent request for the same token gets `nil` and is rejected.
- **Token not found.** Any unrecognized or malformed token at `GET /magic_link_callback/:token` shows the invalid-token alert and redirects — authenticated visitors go to `root_path`, unauthenticated visitors go to `new_session_path`.

---

## Flow 3 — OAuth sign-in (Google / GitHub)

**Config:** OAuth credentials must be present in `bin/rails credentials:edit --environment development`. Without them, clicking an OAuth button triggers the `/auth/failure` callback and shows an error alert on the sign-in page.

### New user, provider email verified

1. Navigate to `/session/new` and click **Sign in with Google** (or GitHub).
   The browser is sent to `/auth/:provider`, then redirects to the provider, then returns to `/auth/:provider/callback`.
2. The callback reaches `OmniauthCallbacksController#create`.
   `Authentication.find_by(provider:, uid:)` finds nothing. `Current.user` is nil.
   `handle_new_user_oauth` is called.
3. `oauth_email_verified?` returns `true` (Google explicitly sets `email_verified`, GitHub is implicitly trusted).
   `handle_verified_email_oauth` finds or creates a user by email.
   **Expect:** You are signed in immediately and redirected to `after_authentication_url`. No verification email is sent.

### New user, provider email **un**verified

This path applies when Google explicitly returns `info.email_verified: false`.

1. Same flow as above through the callback.
   `oauth_email_verified?` returns `false`.
   `handle_unverified_email_oauth` is called.
2. The user record is created and an email `Authentication` is saved as **pending** (no `verified_at`). The pending invitation/join-link tokens from the session (if present) are persisted onto this authentication for deferred claiming.
   **Expect:** You are **not** signed in. You are redirected to `new_session_path` with a notice: check your email. A verification link email is dispatched — check `/letter_opener`.
3. Click the verification link in `/letter_opener`.
   `Settings::ConnectedAccountsController#verify` verifies the authentication, signs you in (because `was_authenticated` is false), claims any pending invitation or join-link, and redirects to `root_path`.

### Signed-in user linking a provider

1. Sign in with email/password, then navigate to `settings/connected_accounts` (the sidebar item labelled **Security**).
2. Click **Connect Google** (or GitHub). The browser returns to the callback.
   `Current.user` is present; `handle_signed_in_link` is called.
3. If the OAuth email **matches** the account's primary email and `email_verified` is true: the authentication is created and immediately verified.
   **Expect:** Redirect to `settings/connected_accounts` with a "linked" notice. The provider now appears in the list as verified.
4. If the OAuth email does **not** match (or `email_verified` is false): the authentication is saved as pending. A verification link email is dispatched to the OAuth address — check `/letter_opener`.
   **Expect:** Redirect to `settings/connected_accounts` with a "pending" notice. The provider appears in the list with a "Verify" / "Resend" / "Remove" action.
5. Click the verification link in `/letter_opener`.
   **Expect:** The authentication is verified, the pending entry is updated to verified, and you are redirected to `settings/connected_accounts` with a success notice (you were already authenticated, so `was_authenticated` is true — no re-sign-in).

### Removing a provider (`settings/connected_accounts`)

Navigate to `settings/connected_accounts`. Next to a verified provider, click **Remove**.

- **Expect (multiple verified authentications):** The provider is removed. Redirect with success notice.
- **Expect (last verified authentication):** The request is rejected. `destroyed_auth.only_verified_remaining?` returns true; the destroy is skipped. Redirect with "cannot remove last verified" alert. This prevents locking the user out of their account.

### Edge cases — OAuth

- **Cross-user collision.** If an attacker attempts to link a Google identity that is already linked to a different account, the legitimate owner receives a defense-in-depth collision-alert email (rate-limited), and the attacker is shown a generic "already linked" alert.
- **Pending re-hit.** If you click an OAuth button while a pending (unverified) authentication for that provider already exists, you are redirected to `settings/connected_accounts` with a "pending in progress" alert and the verification email is re-sent (subject to the per-recipient throttle).

---

## Flow 4 — Workspace creation and joining

### Creating a workspace

**Config:** `TENANCY_WORKSPACE_CREATION=enabled` (default).

1. Sign in and navigate to `/workspaces/new`.
   **Expect:** The new-workspace form is shown.
2. Fill in a name and submit.
   **Expect:** The workspace is created. You are assigned the `owner` role (the controller calls `workspace.memberships.create!(user: Current.user, role: owner_role)` immediately after `workspace.save`). You are redirected to `workspace_path(@workspace)`.

**Config: `TENANCY_WORKSPACE_CREATION=disabled`.** The `before_action :ensure_workspace_creation_enabled` guard on `new` and `create` fires. Navigate to `/workspaces/new` — expect a redirect or error, not the form.

### Joining via an open link

**Config required:**

1. `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link` — the instance ceiling must include `open_link`.
2. The target workspace's join policy must be set to `open_link`. A workspace owner navigates to the workspace settings and enables the shareable link (this sets `workspace.join_policy = "open_link"` and creates a `WorkspaceJoinLink`).
3. The workspace must not be `personal?` — personal workspaces are locked to invite-only at the model level.

**Walkthrough — authenticated user joins:**

1. Copy the join URL for the workspace (format: `/workspaces/:slug/joins/:token`).
2. In the same browser session (signed in, not yet a member), navigate to that URL.
   `Workspaces::JoinsController#show` is called. The `before_action :set_workspace_and_link` validates the workspace, link, and `workspace.open_join?`. On success the confirmation page renders.
   **Expect:** A confirmation page — not a join yet. The GET is intentionally read-only to prevent prefetch and link-unfurlers from triggering automatic admission.
3. Click **Join** (the confirmation form submits `POST /workspaces/:slug/joins/:token`).
   `admit_authenticated_user` calls `workspace.admit(Current.user, role: workspace.default_self_join_role)`.
   **Expect:** Redirect to `workspace_path(@workspace)` with "joined" notice. You are now a member.

**Walkthrough — unauthenticated visitor joins (Flow B):**

1. In a private window (no session), navigate to the join URL.
   **Expect:** Confirmation page renders (same view — `authenticated?` check in `show` does not exist; the before_action only validates the link, not auth state). An existing member who navigates here is immediately redirected to the workspace.
2. Click **Join** (`POST /workspaces/:slug/joins/:token`).
   `stash_for_signup` stores the link token in `session[:pending_join_token]` and redirects to `/registrations/new`.
   **Expect (open signup):** Registration form renders. Fill in and submit.
   **Expect (invite-only):** Registration form still renders — the pending join-link token satisfies `signups_open?` even under `invite_only`.
3. After registration, a verification email is dispatched — check `/letter_opener`. The join token is persisted on the email `Authentication` (`pending_join_link_token`).
4. Click the verification link in `/letter_opener`.
   `Settings::ConnectedAccountsController#verify` verifies the authentication, then calls `auth.claim_pending_join_link!`, which calls `workspace.admit` if the link is still valid.
   **Expect:** You are signed in. If the link was still valid, you are now a member of the workspace. Stale conditions (revoked link, policy changed back to invite, instance allowlist tightened) are silently no-op'd — sign-in proceeds and you land without workspace membership.

### Edge cases — Workspace join

- **Already a member.** If an authenticated user who is already in the workspace navigates to the join URL, `show` immediately redirects to `workspace_path(@workspace)`.
- **Revoked link.** `set_workspace_and_link` checks `join_links.active` (where `revoked_at: nil`). A revoked token produces a neutral "invalid or revoked" alert regardless of which condition failed — no information leakage about workspace existence or join policy.
- **Personal workspace.** `workspace.open_join?` returns false for personal workspaces (the model validates this). The join URL for a personal workspace always produces the "invalid or revoked" alert.
- **`open_link` removed from allowlist.** Removing `open_link` from `SIGNUP_PERMITTED_JOIN_STRATEGIES` takes effect immediately at runtime — `SignupPolicy.permits_strategy?(:open_link)` returns false, `open_join?` returns false, existing join links still exist in the database but are unusable.

---

## Flow 5 — Identity surfaces

### `/me` — identity card

1. Sign in and navigate to `/me` (reachable from the user/avatar menu's "Your home" item, or directly by URL).
   **Expect:** A card showing your avatar, full name, and email address, with an "Edit in settings" button (links to `edit_settings_profile_path`). Below it, a "Your workspaces" section listing every workspace you belong to (`Current.user.memberships.kept.includes(:workspace, :role)`), each showing workspace name, your role, and linking to `workspace_path(membership.workspace)`.
2. If you have no workspace memberships the section shows an empty-state message — not an error.

### `/settings` — account settings

Navigate into the settings hub. The sidebar shows these items in personal context (always visible, no Pundit gating):

| Sidebar label | Path | What it covers |
|---|---|---|
| Profile | `GET /settings/profile/edit` | Display name and email address. |
| Notifications | `GET /settings/notification_preferences/edit` | Per-channel and digest preferences. |
| Security | `GET /settings/connected_accounts` | Linked OAuth providers, verification status, resend, remove, password change. |
| Appearance | `GET /settings/theme_preference/edit` | Light / dark / system theme toggle. |

**Password.** An account that was created via email/password has a Password item accessible from the Security section (`settings/password/new`). An account that was created via OAuth or magic-link may not have a password — check the presence of the form.

**Timezone.** Timezone is set automatically by a client beacon (`settings/preferences/timezone`). There is no manual timezone setting page.

### Header workspace switcher

The header switcher (`shared/_workspace_switcher.html.erb`) renders **only when the user has two or more workspaces** (`workspaces.size > 1`). The partial is hidden via `if workspaces.size > 1`; the DOM element is entirely absent for single-workspace users.

1. Sign in as a user with exactly one workspace.
   **Expect:** No workspace switcher visible in the header. The workspace name is not shown in the nav bar.
2. Join or create a second workspace (requires `TENANCY_WORKSPACE_CREATION=enabled` or an invitation to a second workspace).
   Reload any page.
   **Expect (desktop, ≥`md`):** A workspace switcher dropdown button appears in the header (`hidden md:block`), showing the current workspace's avatar and name (name truncated at 12 characters on large screens). On mobile the switcher lives inside the hamburger menu instead — see step 4.
3. Click the switcher button.
   **Expect:** A dropdown menu opens listing all workspaces. The current workspace is marked with a left border (`border-l-4 border-interactive`), a sunken background, bold weight, and `aria-current`. Clicking another workspace navigates to `workspace_path(workspace)` for that workspace.
4. **On mobile** (below `md`), the desktop dropdown is hidden; open the **hamburger menu** — the switcher renders there as a labeled inline list ("Workspaces"), each entry linking to its workspace with the current one marked via `aria-current`. (The user menu's "All workspaces" link → the workspaces index is an alternate switching path on any breakpoint.)

### Edge cases — Identity

- **`/me` requires authentication.** Navigating to `/me` when signed out triggers the authentication guard and redirects to the sign-in page.
- **Settings sidebar in org context.** When the settings layout is loaded in the context of a workspace (e.g., `/workspaces/:slug/edit`), the sidebar shows workspace-scoped items (Profile, Members, Invitations, Limits & Plan), gated by Pundit. Items for which the current user lacks the required permission are omitted — they are not shown as disabled.
- **Removing the last OAuth/email sign-in method.** `Settings::ConnectedAccountsController#destroy` checks `only_verified_remaining?` before destroying. Attempting to remove the last verified authentication method shows the "cannot remove last verified" alert without deleting anything.
