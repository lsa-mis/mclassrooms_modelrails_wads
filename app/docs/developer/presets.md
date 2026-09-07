---
title: App Presets
description: How modelrails_base supports multiple product shapes (Solo-default, Single-tenant, Open SaaS, Workspace-optional) through configuration, and how to pick one
keywords: presets configuration tenancy multi-tenant single-tenant SaaS signup onboarding workspace setup posture none workspace-optional
---

# App Presets

modelrails_base is **always multi-tenant at the data layer** — every row is workspace-scoped through `Current.workspace` and the `Tenanted` concern. What varies across products is the *presentation* of that tenancy: whether users see one workspace or many, whether signup is open or invite-only, and how membership is acquired.

A **preset** is a named combination of four configuration knobs that collapses the multi-tenant architecture into a specific product shape. Four are recognized:

| Preset | Use this for… | Signup | A new user lands in… | More workspaces? |
|---|---|---|---|---|
| **[Solo-default](/docs/developer/presets-solo)** *(ships today)* | Prosumer / multi-workspace tools (Notion-style); private betas | Open or invite-only | A personal workspace (auto-created) | Yes |
| **[Single-tenant](/docs/developer/presets-single-tenant)** *(Reshape 1 — see [#181](https://github.com/dschmura/modelrails_base/issues/181))* | Internal company tools; one-org deployments | Invite-only or SSO | The one shared workspace | No |
| **[Open SaaS](/docs/developer/presets-open-saas)** *(Reshape 2+ — see [#181](https://github.com/dschmura/modelrails_base/issues/181))* | B2B SaaS with per-customer orgs; community products | Open *or* link-gated | An org they create or join | Yes |
| **[Workspace-optional](/docs/developer/presets-none)** *(#343)* | Event / community / personal-dashboard products; user-first auth | Open or invite-only | A workspace-agnostic home (no workspace) | Created/joined explicitly |

The four configuration knobs and the full design rationale are documented in [#181](https://github.com/dschmura/modelrails_base/issues/181); each preset below pins specific values for them.

## Quick decision

If you're building…

- **a tool one user mostly uses solo, occasionally with a small team** → **[Solo-default](/docs/developer/presets-solo)**. You already have it.
- **an internal tool for one company / school / team where everyone shares one workspace** → **[Single-tenant](/docs/developer/presets-single-tenant)**.
- **a SaaS where each customer is their own org and signup is public** → **[Open SaaS](/docs/developer/presets-open-saas)**.
- **an event platform, community, or personal dashboard where workspaces are optional or created explicitly** → **[Workspace-optional](/docs/developer/presets-none)**.

When in doubt, start with **Solo-default** — switching to any of the others is mostly *removing* surface (hiding the switcher, locking signup) rather than adding it.

---

## Switching presets later

**Switching presets on a live app is a migration, not a config edit.** Flipping `WORKSPACE_ON_SIGNUP` later doesn't migrate existing data — for example, `:personal`→`:shared` leaves every user's personal workspace intact and adds them to the shared one. Pick a preset at setup time; mid-life changes require a deliberate migration plan. (Open SaaS has its own mid-life nuance — tightening the join-strategy allowlist — documented on its page.)

Switching **to `:none`** is a special case: it's effectively a from-scratch product shape. Existing users keep their workspaces; the knob change only affects new signups. Landing new users on a workspace-agnostic home requires overriding `authenticated_home_path` (see [Workspace-optional](/docs/developer/presets-none) and [Forking](/docs/developer/forking)) and building a home view that works with no workspace in context. Plan this at setup time.

## Two mechanics that surprise people

**The first-run wizard's step is derived, never persisted.** Under the `:none` posture the only onboarding state on the record is `onboarded_at`; `User#onboarding_step` reads the workspace and project data to decide `:workspace`, `:project`, or `:team`, so the dispatcher, the guard, and the step controllers all get one answer from one place instead of re-deriving it.

**Under `:shared`, signup pre-creates a placeholder membership, and invitation acceptance reconciles it.** `User#onboard_workspace` joins every new user to the shared workspace as a Member (with `self_join: :onboarding`, so nobody is notified about their own arrival). When that user then accepts an invitation carrying a different role, `Workspace#admit` finds the existing kept membership and adopts the invitation's role rather than treating it as a duplicate accept. The `:personal` posture is untouched by this branch. If the shared workspace is not admittable at signup time, registration still succeeds and the user simply joins nothing; a raise there would roll the account back.

## Next steps

Pick the shape you're building and follow its page end-to-end:

- **[Solo-default →](/docs/developer/presets-solo)** — prosumer / multi-workspace tools; the shipped default.
- **[Single-tenant →](/docs/developer/presets-single-tenant)** — one shared workspace for an internal tool or one-org deployment.
- **[Open SaaS →](/docs/developer/presets-open-saas)** — per-customer org workspaces with shareable join links.
- **[Workspace-optional →](/docs/developer/presets-none)** — user-first auth where workspaces are created or joined explicitly.

Then **[Extending ModelRails →](/docs/developer/extending)** to build your own features on top.
