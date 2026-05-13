---
title: Project Collaboration
description: Creating projects, managing members, inviting collaborators, and working with resources
keywords: project members collaboration resources documents invitations roles creator editor viewer pin reposition
audience: [guide, technical]
---

# Project Collaboration

Projects live inside workspaces and provide a space for team collaboration on resources (documents and other content types).

## Creating a Project

**Route:** `POST /workspaces/:slug/projects`

Provide a name and optional description. A URL-safe slug is generated automatically, unique within the workspace. The creator is assigned the **creator** project role and a `ProjectMembership` is created.

Workspace capacity limits apply — if the workspace has reached `max_projects`, creation is blocked.

## Project Roles

Project-level roles are simpler than workspace roles, using a three-tier enum:

| Role | Can edit resources | Can manage members | Assigned how |
|------|-------------------|-------------------|--------------|
| **Creator** | Yes | Yes | Automatically on creation |
| **Editor** | Yes | No | Invitation or member add |
| **Viewer** | No | No | Invitation or member add |

Project roles are checked via `ProjectMembership#role` (an enum), not via the JSON permissions system used at the workspace level.

## Managing Project Members

**Routes:** `/workspaces/:slug/projects/:slug/memberships`

### Adding Members

Select from existing workspace members. A user **must be a workspace member** before they can be added to a project — the `user_is_workspace_member` validation enforces this.

### Inviting External Users

**Route:** `POST /workspaces/:slug/projects/:slug/invitations`

Invite someone who isn't yet a workspace member:

1. Enter their email and choose a project role (editor or viewer).
2. The system sends an invitation email with a 7-day expiry.
3. When the invitee accepts, they become both a workspace member (with viewer role) and a project member (with the specified role).

This dual-level acceptance happens atomically in `Invitation#accept!`.

### Changing Roles

Update a member's project role between creator, editor, and viewer.

### Removing Members

Destroy the `ProjectMembership` record. The user remains a workspace member.

## Pinning Projects

Users can pin their favorite projects for quick access:

**Route:** `PATCH /workspaces/:slug/projects/:slug/memberships/:id/toggle_pin`

The toggle finds the membership via `Current.user` (not the URL param) to prevent IDOR attacks. Pinned projects appear first in the project list.

## Resources

Resources are the content items within a project. The system uses a polymorphic pattern:

```
Project → has_many :resources → belongs_to :resourceable (polymorphic)
```

### Documents

The default (and currently only) resource type. Documents use **Action Text** for rich text editing with Trix:

- `Document` model holds just an ID and timestamps
- Rich text content lives in Action Text's `rich_texts` table via `has_rich_text :body`
- The `Resource` wrapper provides title, status, position, and creator tracking

### Resource Status

| Status | Meaning |
|--------|---------|
| `draft` | Work in progress, visible to project members |
| `published` | Complete, ready for wider consumption |

### Ordering

Resources have a `position` field (integer, >= 0) and can be reordered:

**Route:** `PATCH /workspaces/:slug/projects/:slug/resources/:id/reposition`

The `positioned` scope orders by position ascending.

### Adding New Resource Types

See the [Extending](/docs/extending) guide for how to add new resource types via the polymorphic pattern.

## Soft Delete

Projects use the `Discardable` concern for soft deletion. Deleting a project hides it from all views but preserves data. Workspace deletion cascades to all projects.

## Real-Time Updates

Projects broadcast changes via Turbo Streams:

- `ProjectMembership` broadcasts on create, update, and destroy
- `Resource` broadcasts changes to the project channel
- Connected users see updates in real time
