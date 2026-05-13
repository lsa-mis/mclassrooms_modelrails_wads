---
title: Workspace Administration
description: Creating and managing workspaces, members, invitations, roles, branding, and ownership
keywords: workspace members invitations roles branding ownership transfer settings capacity limits soft delete discard
audience: [guide, technical]
---

# Workspace Administration

A workspace is the top-level organizational boundary. Users, projects, invitations, and roles are all scoped to a workspace.

## Creating a Workspace

Any authenticated user can create a workspace. A URL-safe slug is generated automatically from the name. The creator is assigned the **Owner** role.

**Defaults:** free plan, 5 max members, 3 max projects.

## Workspace Settings

**Route:** `PATCH /workspaces/:slug/settings`  
**Permission:** `manage_settings` (Owner, Admin)

Configure capacity limits:

| Setting | Validation | Purpose |
|---------|-----------|---------|
| `max_members` | Must be > 0 | Cap on active memberships |
| `max_projects` | Must be > 0 | Cap on active projects |

These limits are enforced when creating new memberships or projects. The validation runs inside a database lock to prevent race conditions.

## Member Management

**Routes:** `/workspaces/:slug/members`  
**Permission:** `manage_members` (Owner, Admin)

### Viewing Members

The members index supports:

- **Search** by first name, last name, or email
- **Filter** by role (Owner, Admin, Member, Viewer) or status (Active, Deactivated)
- **Sort** by name, email, role, or join date
- **Pagination** via Pagy

### Changing a Member's Role

Select from the workspace's effective roles (system defaults plus any workspace-specific custom roles).

### Deactivating a Member

Deactivation is a **soft operation** — the membership is discarded (not destroyed), and the user is removed from all projects in that workspace. The last owner cannot be deactivated.

### Reactivating a Member

Restores a previously deactivated membership. The user regains workspace access but must be re-added to individual projects.

## Ownership Transfer

**Permission:** `manage_workspace` (Owner only)

Transfers ownership atomically:

1. Target member becomes Owner.
2. Current owner is downgraded to Admin.
3. Both changes happen in a single database transaction.

## Invitations

**Routes:** `/workspaces/:slug/invitations`  
**Permission:** `manage_members` (Owner, Admin)

### Email Invitations

1. Enter one or more email addresses (comma or newline separated).
2. Select a role for the invitees.
3. The system creates invitation records and sends emails via `InvitationMailer`.
4. Each invitation has a unique token and **7-day expiry**.

Bulk invite skips emails that are invalid, already members, or already have pending invitations. Returns a count of sent vs. skipped.

### Magic Link Invitations

Creates a shareable URL (no email required). Share the link directly — anyone with it can accept. Useful for Slack channels, team chats, or onboarding docs.

### Accepting an Invitation

- **Existing users:** click the link, sign in if needed, and the invitation is accepted.
- **New users:** click the link, complete registration, and the invitation is auto-accepted.
- **Deactivated members:** accepting re-activates the existing membership.

### Managing Invitations

| Action | What it does |
|--------|-------------|
| Resend | Regenerates the token and extends expiry by 7 days |
| Revoke | Marks the invitation as revoked (link stops working) |

## Roles & Permissions

Roles use a flat JSON permissions structure:

```json
{
  "manage_workspace": true,
  "manage_members": true,
  "manage_projects": true,
  "manage_settings": true
}
```

### System Default Roles

| Role | Permissions |
|------|------------|
| **Owner** | All four permissions |
| **Admin** | manage_members, manage_projects, manage_settings |
| **Member** | manage_projects |
| **Viewer** | None (read-only) |

### Custom Roles

Create workspace-specific roles by seeding `Role` records with `workspace_id` set. They appear alongside system defaults in the role picker. `Workspace#effective_roles` returns both.

### How Permissions Are Checked

Pundit policies call `can?("permission_name")`, which looks up `membership.role.permissions["permission_name"]`. Returns `false` if the membership, role, or permission key doesn't exist.

## Branding

**Routes:** `/workspaces/:slug/branding`  
**Permission:** `manage_settings` (Owner, Admin)

### Logo Sources

- **Upload** — crop an image (PNG, JPEG, GIF, WebP; max 5 MB). The original is stored separately for re-cropping.
- **Initials** — generated from the workspace name (first letter of the first two words).

### Primary Color

A hue value (0–360) that determines the workspace icon's background color via OKLCH. Applied as a CSS custom property (`--hue`) for CSP safety.

## Soft Delete

**Route:** `DELETE /workspaces/:slug`  
**Permission:** `manage_workspace` (Owner, Admin)

Workspaces are soft-deleted via the `Discardable` concern. Deleting a workspace also cascades the soft-delete to all its projects. Memberships and invitations remain in the database but the workspace is hidden from all user-facing views.

## Real-Time Updates

Workspace changes are broadcast via Turbo Streams using the `Broadcastable` concern. Connected users see member list changes, branding updates, and invitation status changes in real time.
