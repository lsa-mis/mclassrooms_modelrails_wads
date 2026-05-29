---
title: App Presets
description: How modelrails_base supports multiple product shapes (Solo-default, Single-tenant, Open SaaS) through configuration, and how to pick one
keywords: presets configuration tenancy multi-tenant single-tenant SaaS signup onboarding workspace setup posture
audience: [guide, technical]
---

# App Presets

modelrails_base is **always multi-tenant at the data layer** — every row is workspace-scoped through `Current.workspace` and the `Tenanted` concern. What varies across products is the *presentation* of that tenancy: whether users see one workspace or many, whether signup is open or invite-only, and how membership is acquired.

A **preset** is a named combination of four configuration knobs that collapses the multi-tenant architecture into a specific product shape. Three are recognized:

| Preset | Use this for… | Signup | A new user lands in… | More workspaces? |
|---|---|---|---|---|
| **[Solo-default](#solo-default)** *(ships today)* | Prosumer / multi-workspace tools (Notion-style); private betas | Open or invite-only | A personal workspace (auto-created) | Yes |
| **[Single-tenant](#single-tenant)** *(Reshape 1 — see [#181](https://github.com/dschmura/modelrails_base/issues/181))* | Internal company tools; one-org deployments | Invite-only or SSO | The one shared workspace | No |
| **[Open SaaS](#open-saas)** *(Reshape 2+ — see [#181](https://github.com/dschmura/modelrails_base/issues/181))* | B2B SaaS with per-customer orgs; community products | Open *or* link-gated | An org they create or join | Yes |

The four configuration knobs and the full design rationale are documented in [#181](https://github.com/dschmura/modelrails_base/issues/181); each preset below pins specific values for them.

## Quick decision

If you're building…

- **a tool one user mostly uses solo, occasionally with a small team** → **Solo-default**. You already have it.
- **an internal tool for one company / school / team where everyone shares one workspace** → **Single-tenant**.
- **a SaaS where each customer is their own org and signup is public** → **Open SaaS**.

When in doubt, start with **Solo-default** — switching to either of the others is mostly *removing* surface (hiding the switcher, locking signup) rather than adding it.

---

## Solo-default

**What it is.** The default shape modelrails_base ships with. Every user auto-gets a *personal* workspace on signup. They can be invited to additional workspaces (org or personal) by other users. The tenancy UI (workspace switcher, "create workspace") surfaces naturally when they belong to more than one workspace.

**Who it's for.** Prosumer / multi-workspace tools — products where a solo user can use the app meaningfully alone (in their personal workspace) but team workspaces are also a first-class concept. Notion, Figma, Linear's personal tier all fit this shape.

**What you get out of the box.** This is the shipped state; no configuration changes are needed to land on it.

| Knob | Value | Mechanism |
|---|---|---|
| `signup.mode` | `:invite_only` (default — set `SIGNUP_MODE=open` to flip) | `config/initializers/signup.rb` |
| `tenancy.onboarding` | `:personal` *(implicit — only path currently built)* | `User#create_personal_workspace` callback runs on user creation |
| `tenancy.workspace_creation` | `:enabled` *(implicit)* | `WorkspacesController#new` accessible to any authenticated user |
| `permitted_join_strategies` | `[:invite]` *(implicit — only mechanism built)* | `Invitation.consume!` is the single membership-grant path |

Three specific behaviors worth knowing:

- **Personal workspaces are hidden from the header switcher dropdown** ([#145](https://github.com/dschmura/modelrails_base/pull/145)) — solo users don't see a switcher until they have at least one *org* workspace.
- **Invitation acceptance is email-bound across every path** (signup / OAuth / magic-link / signed-in accept) — a leaked invite link cannot be redeemed by someone else. Magic-link invitations (no email set) remain intentionally bearer. See PRs [#175](https://github.com/dschmura/modelrails_base/pull/175), [#176](https://github.com/dschmura/modelrails_base/pull/176), [#180](https://github.com/dschmura/modelrails_base/pull/180), [#182](https://github.com/dschmura/modelrails_base/pull/182).
- **Email verification uses Rails 8 `generates_token_for`** — signed, stateless, single-use. See `Authentication#generates_token_for :email_verification`.

**How to verify your setup is Solo-default.** After cloning and bootstrapping (`bin/setup`), open a console:

```bash
bin/rails console
```

```ruby
user = User.create!(
  email_address: "test@example.com",
  first_name: "Test", last_name: "User",
  password: "SecureP@ssw0rd123!", password_confirmation: "SecureP@ssw0rd123!"
)

user.workspaces.count                                  # => 1
user.workspaces.first.personal?                        # => true
user.workspaces.first.memberships.first.role.slug      # => "owner"
```

Three positives confirm the preset: a new user has exactly one workspace, it's flagged personal, and they own it.

Browser verification (optional, requires `SIGNUP_MODE=open` or a valid invitation) — sign up a fresh user and confirm:

1. After verifying their email, they land in their personal workspace.
2. The header workspace switcher does *not* show their personal workspace.
3. `/workspaces/new` is accessible and creates a second workspace.

**When to switch presets.**

- *"Every user should land in one shared workspace — there should* be *no personal workspaces, and the switcher should be gone entirely."* → **Single-tenant** (Reshape 1).
- *"I need self-serve join via shareable links (`open_link`), email-domain auto-join (`domain`), or a request-and-approve flow."* → **Open SaaS** (Reshape 2+).

---

## Single-tenant

**What it is.** One shared workspace, no personal workspaces, the tenancy UI suppressed. Every authenticated user is a member of the same workspace; new signups land there automatically. There is no workspace switcher, no "New workspace" UI, and no way for users to create additional workspaces.

**Who it's for.** Internal company tools, one-org deployments, classroom/cohort tools with central administration — any product where "the workspace" is implicit and there's no need to expose tenancy as a user-facing concept.

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
   | `TENANCY_ONBOARDING` | yes | `shared` | Selects this preset |
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
2. The header workspace switcher does not appear.
3. `/workspaces/new` redirects to root with the alert `Workspace creation is disabled on this instance.`
4. Invited new users (via the standard invitation flow) verify their email and become Members of the same shared workspace.

**When to switch presets.**

- *"Users should each get their own personal workspace; this is too restrictive."* → **Solo-default**.
- *"Each customer should have their own workspace, and signup should be public."* → **Open SaaS** (Reshape 2+).

**Switching presets on a live app is a migration, not a config edit.** Flipping `TENANCY_ONBOARDING` later doesn't migrate existing data — for example, `:personal`→`:shared` leaves every user's personal workspace intact and adds them to the shared one. Pick a preset at setup time; mid-life changes require a deliberate migration plan.

---

## Open SaaS

The public-SaaS / multi-workspace shape: per-workspace control over how new members join. Workspace admins choose between **invite-only** and a **shareable open link** for each workspace they own. Built incrementally across Reshape 2 slices.

**Current status (Reshape 2b shipped):**

| Capability | Status |
|---|---|
| Per-workspace `join_policy` (invite / open_link) | ✅ |
| `WorkspaceJoinLink` model + atomic rotate + revoke | ✅ |
| Workspace settings UI (radio + active link + copy/rotate/revoke) | ✅ |
| Instance allowlist (`SIGNUP_PERMITTED_JOIN_STRATEGIES`) | ✅ |
| Flow A — *existing* authenticated user joins via link | ✅ |
| Flow B — *new* user via link (link opens the signup gate) | ✅ |
| `:domain` strategy (verified-email-domain auto-join) | ⏳ Reshape 3 |

**What you get when configured.**

| Knob | Value | Mechanism |
|---|---|---|
| `signup.mode` | `:open` *or* `:invite_only` — see posture below | `config/initializers/signup.rb` (`SIGNUP_MODE`) |
| `tenancy.onboarding` | `:personal` — each user gets a personal workspace, then creates/joins orgs | `User#onboard_workspace` |
| `tenancy.workspace_creation` | `:enabled` — users can create org workspaces | `WorkspacesController#new` |
| `permitted_join_strategies` | `[:invite, :open_link]` | `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link` |

Open SaaS is **Solo-default's tenancy** (personal onboarding, workspace creation on) **plus the `open_link` join strategy** — so a workspace Owner can hand out a shareable join link instead of inviting people one by one.

### Signup posture — pick one

Open SaaS supports two front-door postures. They differ *only* in whether a stranger can create an account with no invitation and no link; both give workspace Owners/Admins identical control over their own members.

| | **Fully public** | **Controlled-growth** |
|---|---|---|
| `SIGNUP_MODE` | `open` | `invite_only` |
| `SIGNUP_PERMITTED_JOIN_STRATEGIES` | `invite,open_link` | `invite,open_link` |
| Who can create an account | anyone, at `/sign-up` | only via an invitation or a valid open-link token |
| Good for | self-serve products, communities | B2B, controlled betas, "every user vouched-for" |

Choose by whether you want an **anonymous front door**. `open` maximizes self-serve discovery. `invite_only + open_link` means every account traces to an invitation or a shared link — no cold signup — at the cost of no organic self-registration.

**The two knobs are independent.** `SIGNUP_MODE` controls *who may create an account*; `SIGNUP_PERMITTED_JOIN_STRATEGIES` controls *which join mechanisms exist*. Setting `SIGNUP_MODE=open` does **not** enable shareable links — you still need `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link` for that. Both postures above set the strategies allowlist explicitly for exactly this reason.

> **`SIGNUP_MODE` is not how you "get an admin."** It only controls the anonymous front door. Your admin account, and the power to invite / approve / remove members, come from a workspace **Owner/Admin role** (`manage_members`) — present in *either* posture. There is no instance-wide super-admin: administration is per-workspace, so a user who self-registers under `open` owns and administers their own workspace. If you need cross-instance user administration, that's a feature to build, not a `SIGNUP_MODE` setting.

**Verify the strategy is enabled.** With `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link` set, in `bin/rails console`:

```ruby
SignupPolicy.permits_strategy?(:open_link)   # => true

w = Workspace.create!(name: "Acme", personal: false, join_policy: "open_link")
w.open_join?                                  # => true (open to link-joins)
```

If `permits_strategy?(:open_link)` is `false`, the env var isn't set — links will be inert and the join-policy radio won't offer "Shareable join link".

**Setup (Reshape 2a — Flow A):**

1. Set `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link` (default is `invite` alone — preserves Solo-default).
2. Owner/Admin opens their workspace's `/workspaces/:slug/settings/edit` and selects "Shareable join link" under Join policy.
3. The settings page shows the active link with **Copy / Rotate / Revoke** controls. The link follows the form `/workspaces/:slug/joins/:token`.
4. Share the link with anyone who has an account on this instance — clicking lands them on a confirmation page; the Join button admits them as a Member.

**Key behaviors (Reshape 2a):**

- **Personal workspaces are hard-guarded** — `Workspace#open_join?` returns `false` for personal workspaces regardless of `join_policy`. A personal workspace cannot be configured as `open_link` (validation rejects).
- **Instance allowlist enforced at two layers** — model validation (admins can't *set* `:open_link` when the instance forbids it) AND runtime guard (`Workspace#open_join?` re-checks defense-in-depth).
- **Atomic rotate** — clicking "Rotate" revokes the current link and creates a new one in one transaction. The previous link stops working immediately.
- **Capacity respected** — `Workspace#admit` honors `max_members`; an over-capacity join surfaces a clean error.
- **Single membership-grant entry point** — both invitation acceptance and link self-join go through `Workspace#admit`, sharing the same lock, capacity, and (under `:shared` posture) role-reconciliation logic.
- **Settings UI auto-hidden under `:shared` posture** — single-tenant deployments don't see the join-policy section.

**Setup (Reshape 2b — Flow B):** Already enabled by the same `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link` setting from 2a. The Flow B path is automatic:

1. Brand-new visitor (no account) clicks a shareable join link.
2. `Workspaces::JoinsController#create` stashes the token in `session[:pending_join_token]` and redirects to `/sign-up`.
3. `SignupPolicy.allows_signup?` checks `workspace_join_acceptable?` — the open-link token opens the gate even under `SIGNUP_MODE=invite_only`. The signup form renders.
4. Visitor registers. `RegistrationsController#create` parks the token on the new email `Authentication` (`pending_join_link_token`), clears the session, sends the verification email.
5. Visitor clicks the verification email link. `Account::ConnectedAccountsController#verify` proves email ownership, then `Authentication#claim_pending_join_link!` admits them to the workspace as Member via `Workspace#admit`.

Stale conditions at claim time (link revoked, workspace policy reverted to `:invite`, instance allowlist no longer permits `:open_link`) are silently no-op'd — email verification proceeds and the user lands signed in but without the workspace membership. Capacity errors at claim time surface as a flash without blocking sign-in.

**Tightening the allowlist on a live app.** Removing `open_link` from `SIGNUP_PERMITTED_JOIN_STRATEGIES` (e.g. reverting to `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite`) takes effect **immediately at runtime** — there is no data migration. `Workspace#open_join?` re-checks the allowlist on every call, so all existing shareable links stop working at once and both Flow A and Flow B silently no-op. Workspaces keep their stored `join_policy: "open_link"` value, but it is now inert.

That stale value has one sharp edge: `join_policy_must_be_permitted_by_instance` validates on **every save**, so a workspace still carrying `open_link` becomes unsaveable — editing any unrelated field (name, color, …) fails with *"Join policy is not permitted by this instance"* — until its policy is reset.

**Reset command.** Reconcile stale workspaces back to a permitted policy from the Rails console (`bin/rails console`). `update_all` is deliberate here — it bypasses the very validation that would otherwise block the fix:

```ruby
# Reset every workspace still carrying the now-forbidden open_link policy.
Workspace.where(join_policy: "open_link").update_all(join_policy: "invite")
```

Their already-issued join links stay in the table but are inert (`open_join?` is `false`). Leave them, or revoke individually via the settings UI or `link.revoke!`.

**When to switch presets.**

- *"I want to lock signup entirely; users should only join via admin invitation."* → keep `SIGNUP_PERMITTED_JOIN_STRATEGIES=invite` and the per-workspace radio defaults to invite — this *is* Solo-default with no further changes.
- *"Everyone should be in one shared workspace with no join UI at all."* → **Single-tenant** preset (Reshape 1).

## Next steps

With your app shape chosen, **[Extending ModelRails →](/docs/extending)** walks through adding your own workspace-scoped models, authorization, and features on top of it.
