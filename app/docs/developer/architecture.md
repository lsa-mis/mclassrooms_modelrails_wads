---
title: Architecture
description: Data model, authorization, and real-time patterns in ModelRails
keywords: models workspace membership pundit authorization turbo streams multi-tenancy tenanted
---

# Architecture

## Data Model Hierarchy

```
User
  └── Workspace (personal, auto-created on sign-up)
  └── Workspace (organizational, created manually)
        ├── Membership (user + Role with permissions JSON)
        └── Invitation (polymorphic — currently workspace only)
```

The template ships this workspace/membership/role/invitation core deliberately
thin — the example domain that previously hung off `Workspace` (a demo
collaboration model and its nested records) has been removed so a fork's own
domain models can take its place. The `Tenanted` concern (see below) and the
`draw(:app)` routing seam exist specifically so a fork's tenant-scoped models
drop in without touching template code.

## Key Concepts

**Workspace** — organizational boundary. Billing, roles, member management. Every user has a personal workspace created on sign-up.

**Role** — workspace-level roles with permissions JSON. Four system defaults: Owner, Admin, Member, Viewer. Forkers add custom roles via seeds.

**Tenanted** (`app/models/concerns/tenanted.rb`) — the fork's extension seam for tenant-scoped domain models: `include Tenanted` on a model with `belongs_to :workspace` to get a `.for_current_workspace` scope keyed off `Current.workspace`. See the "Deliberate architectural deviations" section of `CLAUDE.md` for the tradeoff this concern accepts.

## Authorization

Pundit policies check permissions at the workspace level: `ApplicationPolicy#can?("permission_name")` reads from `role.permissions` JSON. A fork's own tenant-scoped models add their own policies alongside this pattern.

Authorization is opt-in per action (there is no global `verify_authorized`), but it's **enforced at CI**: `spec/code_smells/mutating_actions_are_authorized_spec.rb` walks every mutating (POST/PATCH/PUT/DELETE) route and fails the suite if the action neither calls `authorize` nor is on a reviewed allow-list. The allow-list holds only actions that are public auth-entry flows or act solely on the current user's own resources. So a new mutating controller that forgets `authorize` on a tenant resource fails a test rather than shipping a silent IDOR — add the `authorize` call, or add the action to the allow-list with a one-line rationale if it's genuinely public/self-scoped. Pairs with the tenant-load guard (`no_unscoped_tenant_loads_spec`): that one stops loading the wrong record, this one stops the missing check.

**Granting roles** is gated separately by `ApplicationPolicy#may_grant?(role)`: an actor can grant a role only if they already hold every permission it confers (a superset check, not a rank). This blocks privilege escalation — e.g. an Admin promoting anyone to Owner — and `MembershipPolicy#update?`/`#reactivate?` additionally refuse to manage a membership whose role the actor couldn't grant. `Workspace#admit` (invitation-accept / open-link self-join) deliberately does **not** re-check this: the role is authorized when the invitation or link is *created* (`authorize_role_grant!`), not when redeemed. If you add a new membership-grant entry point, gate the role where it is minted, not where it is consumed.

## Activity Tracking

The `Trackable` concern auto-creates `ActivityLog` records via `after_commit` callbacks. Models opt in with `include Trackable`. Sensitive attributes (tokens, passwords) are stripped from metadata.

## Real-Time

Turbo Stream broadcasts via `broadcast_refresh_to` (Turbo 8 morph-based refresh). Workspace stream for membership/invitation/settings changes.

## Markdowndocs Gem Integration

The `markdowndocs` gem renders this site's `/docs` content. Two host-side adaptations layer on top of the gem's defaults so it fits this app's design system and CSP:

**View overrides** (`app/views/markdowndocs/docs/`) — six ERB files (`show`, `index`, `_card`, `_breadcrumb`, `_navigation`, `_mode_switcher`) that mirror the gem's templates but route every color through this app's semantic tokens (`bg-surface-raised`, `text-text-heading`, `text-accent`, etc.) instead of the gem's hardcoded Tailwind palette pairs. The token system flips coherently with `class="dark"` on `<html>`. Rails view resolution prefers `app/views/` over engine view paths, so these overrides take precedence at render time.

**Mobile sidebar Stimulus controller** (`app/javascript/controllers/docs_sidebar_controller.js`) — replaces the gem's inline `onclick` handler for the mobile hamburger toggle. The host's CSP locks `script-src` to `:self` with nonces and disallows `unsafe-inline`, so the host override of `show.html.erb` wires the toggle via Stimulus actions instead.

Both layers can be removed if the gem itself starts shipping token-friendly templates and CSP-clean Stimulus interactivity. Until then, see [troubleshooting.md](/docs/developer/troubleshooting) if a class fails to compile or a controller fails to register.
