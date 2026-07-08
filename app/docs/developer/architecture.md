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

## Activity Tracking

The `Trackable` concern auto-creates `ActivityLog` records via `after_commit` callbacks. Models opt in with `include Trackable`. Sensitive attributes (tokens, passwords) are stripped from metadata.

## Real-Time

Turbo Stream broadcasts via `broadcast_refresh_to` (Turbo 8 morph-based refresh). Workspace stream for membership/invitation/settings changes.

## Markdowndocs Gem Integration

The `markdowndocs` gem renders this site's `/docs` content. Two host-side adaptations layer on top of the gem's defaults so it fits this app's design system and CSP:

**View overrides** (`app/views/markdowndocs/docs/`) — six ERB files (`show`, `index`, `_card`, `_breadcrumb`, `_navigation`, `_mode_switcher`) that mirror the gem's templates but route every color through this app's semantic tokens (`bg-surface-raised`, `text-text-heading`, `text-accent`, etc.) instead of the gem's hardcoded Tailwind palette pairs. The token system flips coherently with `class="dark"` on `<html>`. Rails view resolution prefers `app/views/` over engine view paths, so these overrides take precedence at render time.

**Mobile sidebar Stimulus controller** (`app/javascript/controllers/docs_sidebar_controller.js`) — replaces the gem's inline `onclick` handler for the mobile hamburger toggle. The host's CSP locks `script-src` to `:self` with nonces and disallows `unsafe-inline`, so the host override of `show.html.erb` wires the toggle via Stimulus actions instead.

Both layers can be removed if the gem itself starts shipping token-friendly templates and CSP-clean Stimulus interactivity. Until then, see [troubleshooting.md](/docs/developer/troubleshooting) if a class fails to compile or a controller fails to register.
