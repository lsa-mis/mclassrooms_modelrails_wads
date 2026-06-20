---
title: Architecture
description: Data model, authorization, and real-time patterns in ModelRails
keywords: models workspace project resource membership pundit authorization turbo streams multi-tenancy client clientside project-tools
audience: [guide, technical]
---

# Architecture

## Data Model Hierarchy

```
User
  └── Workspace (personal, auto-created on sign-up)
  └── Workspace (organizational, created manually)
        ├── Membership (user + Role with permissions JSON)
        ├── Invitation (polymorphic — workspace or project or client)
        └── Project (collaboration space)
              ├── ProjectMembership (user + enum role: creator/editor/viewer)
              ├── ClientAccess (external client ↔ project; NOT a Membership)
              └── Resource (polymorphic registry)
                    └── Document (Action Text rich content)
```

## Key Concepts

**Workspace** — organizational boundary. Billing, roles, member management. Every user has a personal workspace created on sign-up.

**Project** — collaboration boundary. Lightweight, purpose-driven. Who works together on what.

**Resource** — content within a project. Polymorphic registry pattern: `Resource` holds title, status, position; type-specific content lives in the resourceable (e.g., `Document`). Resources with `shared_with_client: true` and `status: published` are visible in the client area.

**Role** — workspace-level roles with permissions JSON. Four system defaults: Owner, Admin, Member, Viewer. Forkers add custom roles via seeds.

**ProjectMembership** — project-level roles as a simple enum (creator/editor/viewer). Upgrade path to Role model documented.

**ClientAccess** — external client's scoped access to a single project. A client is a regular `User`; this row is the external relationship — deliberately NOT a `Membership`, so clients never enter workspace Pundit policies or member-seat counting. `Discardable` (soft-deletable). Only createable when `project.clientside_enabled?` is true. See `app/models/client_access.rb`.

**ProjectTools::Registry** + **ProjectTools::Tool** — code-defined catalogue of per-project tools (navigable sections of a project). Defined in `app/lib/project_tools/`. Each `Tool` is an immutable value object (`Data.define`) with a key, a route helper, and default-enabled/implemented flags. The per-project enabled set is stored as a JSON array in `projects.enabled_tools`; `Project#tools` returns the intersection of the registry's implemented tools and the project's enabled set.

## Authorization

Pundit policies check permissions at two levels:

- **Workspace level**: `ApplicationPolicy#can?("permission_name")` reads from `role.permissions` JSON
- **Project level**: `ProjectPolicy` and `ResourcePolicy` check `project_membership.creator?` / `.editor?` / `.viewer?`

The `Clientside::` controller namespace is a distinct, authenticated access axis that never sets `Current.workspace` and is never covered by workspace Pundit policies. Project resolution in that namespace is gated on a kept `ClientAccess` record — slug knowledge alone grants nothing. See the [Security](/docs/security) page for the full threat model.

## Activity Tracking

The `Trackable` concern auto-creates `ActivityLog` records via `after_commit` callbacks. Models opt in with `include Trackable`. Sensitive attributes (tokens, passwords) are stripped from metadata.

## Real-Time

Turbo Stream broadcasts via `broadcast_refresh_to` (Turbo 8 morph-based refresh). Workspace stream for membership/invitation/settings. Project stream for resource changes.

## Markdowndocs Gem Integration

The `markdowndocs` gem renders this site's `/docs` content. Two host-side adaptations layer on top of the gem's defaults so it fits this app's design system and CSP:

**View overrides** (`app/views/markdowndocs/docs/`) — six ERB files (`show`, `index`, `_card`, `_breadcrumb`, `_navigation`, `_mode_switcher`) that mirror the gem's templates but route every color through this app's semantic tokens (`bg-surface-raised`, `text-text-heading`, `text-accent`, etc.) instead of the gem's hardcoded Tailwind palette pairs. The token system flips coherently with `class="dark"` on `<html>`. Rails view resolution prefers `app/views/` over engine view paths, so these overrides take precedence at render time.

**Mobile sidebar Stimulus controller** (`app/javascript/controllers/docs_sidebar_controller.js`) — replaces the gem's inline `onclick` handler for the mobile hamburger toggle. The host's CSP locks `script-src` to `:self` with nonces and disallows `unsafe-inline`, so the host override of `show.html.erb` wires the toggle via Stimulus actions instead.

Both layers can be removed if the gem itself starts shipping token-friendly templates and CSP-clean Stimulus interactivity. Until then, see [troubleshooting.md](/docs/troubleshooting) if a class fails to compile or a controller fails to register.
