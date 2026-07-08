---
title: Single-tenant
description: Stand up and verify the Single-tenant preset — one shared workspace, no personal workspaces, tenancy UI suppressed
keywords: single-tenant preset shared workspace internal tool owner bootstrap seed owner_setup_link invite-only
---

[App Presets](/docs/developer/presets) › Single-tenant

# Single-tenant

**What it is.** One shared workspace, no personal workspaces, the tenancy UI suppressed. Every authenticated user is a member of the same workspace; new signups land there automatically. There is no workspace switcher, no "New workspace" UI, and no way for users to create additional workspaces.

**Who it's for.** Internal company tools, one-org deployments, classroom/cohort tools with central administration — any product where "the workspace" is implicit and there's no need to expose tenancy as a user-facing concept.

## How users relate

Everyone shares **one** workspace. Each person (with how they **sign in**) is a member of the same Acme workspace; signup is invite-only, so people are invited straight in — and there are no personal workspaces:

<svg viewBox="0 0 720 350" width="100%" role="img" aria-label="Single-tenant: everyone is a member of one shared Acme workspace. Alice: Owner, bootstrapped at deploy, signs in with email and password. Bob: Member, joined via invitation, signs in with Google OAuth. Carol: Admin, joined via invitation, signs in with a magic link. There are no personal workspaces and signup is invite-only." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs>
    <marker id="arrow-single-tenant" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto">
      <path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/>
    </marker>
  </defs>

  <circle cx="42" cy="56" r="22" stroke-width="1.5"/>
  <text x="42" y="62" text-anchor="middle" fill="currentColor" stroke="none" font-size="16" font-weight="700">A</text>
  <text x="80" y="50" fill="currentColor" stroke="none" font-size="14.5" font-weight="600">Alice</text>
  <text x="80" y="70" fill="currentColor" stroke="none" font-size="11" opacity="0.7">signs in: email + password</text>

  <circle cx="42" cy="170" r="22" stroke-width="1.5"/>
  <text x="42" y="176" text-anchor="middle" fill="currentColor" stroke="none" font-size="16" font-weight="700">B</text>
  <text x="80" y="164" fill="currentColor" stroke="none" font-size="14.5" font-weight="600">Bob</text>
  <text x="80" y="184" fill="currentColor" stroke="none" font-size="11" opacity="0.7">signs in: Google OAuth</text>

  <circle cx="42" cy="284" r="22" stroke-width="1.5"/>
  <text x="42" y="290" text-anchor="middle" fill="currentColor" stroke="none" font-size="16" font-weight="700">C</text>
  <text x="80" y="278" fill="currentColor" stroke="none" font-size="14.5" font-weight="600">Carol</text>
  <text x="80" y="298" fill="currentColor" stroke="none" font-size="11" opacity="0.7">signs in: magic link</text>

  <rect class="text-accent" x="500" y="120" width="202" height="104" rx="16" stroke-width="2.25"/>
  <text x="601" y="166" text-anchor="middle" fill="currentColor" stroke="none" font-size="17" font-weight="700">Acme</text>
  <text x="601" y="188" text-anchor="middle" fill="currentColor" stroke="none" font-size="11.5" opacity="0.7">the shared workspace</text>

  <path class="text-accent" d="M280 54 Q 410 70 496 150" stroke-width="2.25" marker-end="url(#arrow-single-tenant)"/>
  <text x="368" y="44" text-anchor="middle" fill="currentColor" stroke="none" font-size="11">Owner · bootstrapped</text>

  <path class="text-accent" d="M280 168 Q 392 168 496 172" stroke-width="2.25" marker-end="url(#arrow-single-tenant)"/>
  <text x="384" y="150" text-anchor="middle" fill="currentColor" stroke="none" font-size="11">Member · via invitation</text>

  <path class="text-accent" d="M280 282 Q 410 274 496 196" stroke-width="2.25" marker-end="url(#arrow-single-tenant)"/>
  <text x="372" y="300" text-anchor="middle" fill="currentColor" stroke="none" font-size="11">Admin · via invitation</text>

  <text x="360" y="338" text-anchor="middle" fill="currentColor" stroke="none" font-size="11" opacity="0.7">One shared workspace · no personal workspaces · signup is invite-only</text>
</svg>

**What you get when configured.**

| Knob | Value | Mechanism |
|---|---|---|
| `signup.mode` | typically `:invite_only` (your call) | `config/initializers/signup.rb` |
| `tenancy.onboarding` | `:shared` | `User#onboard_workspace` dispatches to `join_shared_workspace` |
| `tenancy.workspace_creation` | `:disabled` | `WorkspacesController` `before_action` redirects `:new`/`:create` |
| `permitted_join_strategies` | `[:invite]` *(implicit — only mechanism built)* | `Invitation.consume!` is the single membership-grant path |

The workspace switcher auto-hides under this preset because every user has exactly one membership (the existing #145 "hide personal from switcher" logic plus the single-membership-no-switcher rule combine naturally — no extra suppression needed).

**Setup steps.**

1. Set the ENV vars before running `bin/setup` (or before deploying):

   | Variable | Required? | Example | Purpose |
   |---|---|---|---|
   | `WORKSPACE_ON_SIGNUP` | yes | `shared` | Selects this preset |
   | `TENANCY_WORKSPACE_CREATION` | yes | `disabled` | Turns off "New workspace" UI + route |
   | `TENANCY_SHARED_WORKSPACE_SLUG` | yes | `acme` | URL-safe slug of the shared workspace |
   | `TENANCY_SHARED_WORKSPACE_NAME` | no | `Acme Inc.` | Display name (defaults to titleized slug) |
   | `TENANCY_OWNER_EMAIL` | yes | `admin@acme.com` | Email of the initial Owner |
   | `TENANCY_OWNER_FIRST_NAME` | no | `Admin` | Display first name (default `Workspace`) |
   | `TENANCY_OWNER_LAST_NAME` | no | `User` | Display last name (default `Owner`) |
   | `SIGNUP_MODE` | yes | `invite_only` | Lock account creation to invitations |
   | `APP_HOST` | no | `app.acme.com` | Host used in the logged workspace URL and in `tenancy:owner_setup_link`'s sign-in link (default `localhost` — set this on staging/prod) |

2. Run `bin/setup` (or `bin/rails db:seed` on an existing app). The seed is idempotent — safe to re-run.

3. The seed creates the shared workspace and the Owner user (with a verified email Authentication and an Owner Membership). In development the password-set email is captured by **Letter Opener** — open `/letter_opener` to see it (it isn't sent over SMTP). In `production` it deliberately does **not** put a credential in the logs (a logged token would linger in log retention past its short expiry); instead it logs the workspace URL and points you to an on-demand task. Mint the Owner's sign-in link when you're ready to use it:

   ```bash
   bin/rails tenancy:owner_setup_link
   ```

   This prints a fresh, short-lived password-set URL — the expiry clock starts when you run it, not at deploy time. Deliver it to the Owner out-of-band (or run it yourself if you're claiming the account). It doubles as a break-glass Owner login if email delivery is ever down.

4. The Owner opens the password-set link, sets a password, signs in. They can then invite other users via the normal invitation flow — **each invitation specifies the role the invitee receives** (Member, Admin, etc.). The Owner remains the single source of new-role-granting authority for the shared workspace; roles can also be changed after signup via the members UI at `/workspaces/:slug/members`.

> **Re-inviting under `:shared` updates the role, it doesn't error.** Because `:shared` onboarding pre-creates a placeholder membership for every new user, `Workspace#admit` *reconciles* — admitting an existing member to a new role updates their role rather than raising "already a member" (the behavior you'd get under the default `:personal` posture). So re-inviting someone at a higher role is a valid way to promote them.

**How to verify your setup is Single-tenant.** After running the seed:

```bash
bin/rails console
```

```ruby
TenancyConfig.shared?                          # => true
TenancyConfig.shared_workspace.slug            # => "acme" (your slug)
TenancyConfig.shared_workspace.personal?       # => false
TenancyConfig.shared_workspace.memberships.count  # => 1 (the seeded Owner)

owner = User.find_by!(email_address: ENV["TENANCY_OWNER_EMAIL"])
owner.workspaces                               # => [<Workspace slug: "acme">]
owner.personal_workspace_id                    # => nil
owner.memberships.first.role.slug              # => "owner"
```

In the browser, after the Owner has set their password and signed in:

1. They land directly in the shared workspace (no switcher, no chooser).
2. The header workspace switcher does not appear, and neither does the user
   menu's "All workspaces" entry point (its switcher-adjacent "see all"
   companion) — both are suppressed under `TenancyConfig.shared?` (see
   `shared/_header.html.erb` and `shared/_user_menu.html.erb`), not merely
   hidden by incidental single-membership math.
3. `/workspaces/new` redirects to root with the alert `Workspace creation is disabled on this instance.`
4. Invited new users (via the standard invitation flow) verify their email and become Members of the same shared workspace.

**When to switch presets.**

- *"Users should each get their own personal workspace; this is too restrictive."* → **[Solo-default](/docs/developer/presets-solo)**.
- *"Each customer should have their own workspace, and signup should be public."* → **[Open SaaS](/docs/developer/presets-open-saas)** (Reshape 2+).

## Next steps

- **[← Compare all presets](/docs/developer/presets)** — the decision matrix and the other two shapes.
- **[Extending ModelRails →](/docs/developer/extending)** — add your own workspace-scoped features on top of this preset.
