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
| **[Solo-default](/docs/presets-solo)** *(ships today)* | Prosumer / multi-workspace tools (Notion-style); private betas | Open or invite-only | A personal workspace (auto-created) | Yes |
| **[Single-tenant](/docs/presets-single-tenant)** *(Reshape 1 — see [#181](https://github.com/dschmura/modelrails_base/issues/181))* | Internal company tools; one-org deployments | Invite-only or SSO | The one shared workspace | No |
| **[Open SaaS](/docs/presets-open-saas)** *(Reshape 2+ — see [#181](https://github.com/dschmura/modelrails_base/issues/181))* | B2B SaaS with per-customer orgs; community products | Open *or* link-gated | An org they create or join | Yes |

The four configuration knobs and the full design rationale are documented in [#181](https://github.com/dschmura/modelrails_base/issues/181); each preset below pins specific values for them.

## Quick decision

If you're building…

- **a tool one user mostly uses solo, occasionally with a small team** → **[Solo-default](/docs/presets-solo)**. You already have it.
- **an internal tool for one company / school / team where everyone shares one workspace** → **[Single-tenant](/docs/presets-single-tenant)**.
- **a SaaS where each customer is their own org and signup is public** → **[Open SaaS](/docs/presets-open-saas)**.

When in doubt, start with **Solo-default** — switching to either of the others is mostly *removing* surface (hiding the switcher, locking signup) rather than adding it.

---

## Switching presets later

**Switching presets on a live app is a migration, not a config edit.** Flipping `TENANCY_ONBOARDING` later doesn't migrate existing data — for example, `:personal`→`:shared` leaves every user's personal workspace intact and adds them to the shared one. Pick a preset at setup time; mid-life changes require a deliberate migration plan. (Open SaaS has its own mid-life nuance — tightening the join-strategy allowlist — documented on its page.)

## Next steps

Pick the shape you're building and follow its page end-to-end:

- **[Solo-default →](/docs/presets-solo)** — prosumer / multi-workspace tools; the shipped default.
- **[Single-tenant →](/docs/presets-single-tenant)** — one shared workspace for an internal tool or one-org deployment.
- **[Open SaaS →](/docs/presets-open-saas)** — per-customer org workspaces with shareable join links.

Then **[Extending ModelRails →](/docs/extending)** to build your own features on top.
