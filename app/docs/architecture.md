---
title: Architecture
description: Data model, authorization, and real-time patterns in ModelRails
keywords: models workspace project resource membership pundit authorization turbo streams multi-tenancy
---

# Architecture

## Data Model Hierarchy

```
User
  └── Workspace (personal, auto-created on sign-up)
  └── Workspace (organizational, created manually)
        ├── Membership (user + Role with permissions JSON)
        ├── Invitation (polymorphic — workspace or project)
        └── Project (collaboration space)
              ├── ProjectMembership (user + enum role: creator/editor/viewer)
              └── Resource (polymorphic registry)
                    └── Document (Action Text rich content)
```

## Key Concepts

**Workspace** — organizational boundary. Billing, roles, member management. Every user has a personal workspace created on sign-up.

**Project** — collaboration boundary. Lightweight, purpose-driven. Who works together on what.

**Resource** — content within a project. Polymorphic registry pattern: `Resource` holds title, status, position; type-specific content lives in the resourceable (e.g., `Document`).

**Role** — workspace-level roles with permissions JSON. Four system defaults: Owner, Admin, Member, Viewer. Forkers add custom roles via seeds.

**ProjectMembership** — project-level roles as a simple enum (creator/editor/viewer). Upgrade path to Role model documented.

## Authorization

Pundit policies check permissions at two levels:

- **Workspace level**: `ApplicationPolicy#can?("permission_name")` reads from `role.permissions` JSON
- **Project level**: `ProjectPolicy` and `ResourcePolicy` check `project_membership.creator?` / `.editor?` / `.viewer?`

## Activity Tracking

The `Trackable` concern auto-creates `ActivityLog` records via `after_commit` callbacks. Models opt in with `include Trackable`. Sensitive attributes (tokens, passwords) are stripped from metadata.

## Real-Time

Turbo Stream broadcasts via `broadcast_refresh_to` (Turbo 8 morph-based refresh). Workspace stream for membership/invitation/settings. Project stream for resource changes.
