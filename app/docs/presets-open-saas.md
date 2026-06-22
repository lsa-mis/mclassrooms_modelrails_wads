---
title: Open SaaS
description: Stand up and verify the Open SaaS preset — per-customer org workspaces, shareable join links, two signup postures
keywords: open-saas preset multi-tenant signup posture open_link join link flow a flow b allowlist tightening
audience: [guide, technical]
---

[App Presets](/docs/presets) › Open SaaS

# Open SaaS

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

## How users relate

An example Acme workspace. Each person (with how they **sign in**) connects to the workspace by their **membership** (role · how they joined). Sign-in is email-first and passwordless by default — a magic link unless a password has been set — with Google/GitHub OAuth alongside:

<svg viewBox="0 0 720 350" width="100%" role="img" aria-label="Acme org workspace. Alice: Owner, created the workspace, signs in with a magic link. Bob: Member, joined via a shareable join link, signs in with Google OAuth. Carol: Admin, joined via an invitation, signs in with email and password. Every user also owns a personal workspace; sign-in is email-first and passwordless by default." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs>
    <marker id="arrow-open-saas" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto">
      <path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/>
    </marker>
  </defs>

  <circle cx="42" cy="56" r="22" stroke-width="1.5"/>
  <text x="42" y="62" text-anchor="middle" fill="currentColor" stroke="none" font-size="16" font-weight="700">A</text>
  <text x="80" y="50" fill="currentColor" stroke="none" font-size="14.5" font-weight="600">Alice</text>
  <text x="80" y="70" fill="currentColor" stroke="none" font-size="11" opacity="0.7">signs in: magic link</text>

  <circle cx="42" cy="170" r="22" stroke-width="1.5"/>
  <text x="42" y="176" text-anchor="middle" fill="currentColor" stroke="none" font-size="16" font-weight="700">B</text>
  <text x="80" y="164" fill="currentColor" stroke="none" font-size="14.5" font-weight="600">Bob</text>
  <text x="80" y="184" fill="currentColor" stroke="none" font-size="11" opacity="0.7">signs in: Google OAuth</text>

  <circle cx="42" cy="284" r="22" stroke-width="1.5"/>
  <text x="42" y="290" text-anchor="middle" fill="currentColor" stroke="none" font-size="16" font-weight="700">C</text>
  <text x="80" y="278" fill="currentColor" stroke="none" font-size="14.5" font-weight="600">Carol</text>
  <text x="80" y="298" fill="currentColor" stroke="none" font-size="11" opacity="0.7">signs in: email + password</text>

  <rect class="text-accent" x="512" y="120" width="190" height="104" rx="16" stroke-width="2.25"/>
  <text x="607" y="166" text-anchor="middle" fill="currentColor" stroke="none" font-size="17" font-weight="700">Acme</text>
  <text x="607" y="188" text-anchor="middle" fill="currentColor" stroke="none" font-size="11.5" opacity="0.7">org workspace</text>

  <path class="text-accent" d="M280 54 Q 410 70 508 150" stroke-width="2.25" marker-end="url(#arrow-open-saas)"/>
  <text x="372" y="44" text-anchor="middle" fill="currentColor" stroke="none" font-size="11">Owner · created it</text>

  <path class="text-accent" d="M280 168 Q 396 168 508 172" stroke-width="2.25" marker-end="url(#arrow-open-saas)"/>
  <text x="384" y="150" text-anchor="middle" fill="currentColor" stroke="none" font-size="11">Member · via join link</text>

  <path class="text-accent" d="M280 282 Q 410 274 508 196" stroke-width="2.25" marker-end="url(#arrow-open-saas)"/>
  <text x="372" y="300" text-anchor="middle" fill="currentColor" stroke="none" font-size="11">Admin · via invitation</text>

  <text x="360" y="338" text-anchor="middle" fill="currentColor" stroke="none" font-size="11" opacity="0.7">Each user also owns a personal workspace · password is optional (passwordless by default)</text>
</svg>

## Signup posture — pick one

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
4. Visitor signs up via magic-link (`MagicLinkCallbacksController#create`). `Signupable#accept_pending_join_link!` admits them to the workspace atomically during signup — no separate email-verification step required for join-link claims.
5. User lands signed in and is immediately a workspace Member.

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
- *"Everyone should be in one shared workspace with no join UI at all."* → **[Single-tenant](/docs/presets-single-tenant)** preset (Reshape 1).

## Next steps

- **[← Compare all presets](/docs/presets)** — the decision matrix and the other two shapes.
- **[Extending ModelRails →](/docs/extending)** — add your own workspace-scoped features on top of this preset.
