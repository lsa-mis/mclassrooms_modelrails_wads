---
title: Roles & Access
description: How MiClassrooms is organized — one shared directory, and the admin / editor / viewer roles
keywords: roles access admin editor viewer directory shared workspace permissions unit editor dashboard
---

# Roles & Access

MiClassrooms runs as a **single shared directory** for the whole university.
There is one classroom directory and everyone works in it — you don't create,
switch, or manage workspaces. Signing in with your U-M account puts you straight
into the directory.

## What you can do depends on your role

MiClassrooms has three levels of access:

| Role | Who | What they can do |
|------|-----|------------------|
| **Viewer** | Any signed-in U-M user | Browse the directory: search Find a Room, open room and building pages, and save rooms to a personal shortlist. |
| **Editor** | Assigned per department / unit | Everything a viewer can do, **plus** edit the rooms in their assigned unit(s) — curated fields, notes, and one-way hiding of a room. |
| **Admin** | Directory administrators | Everything, across all units: edit any room, hide and unhide rooms and buildings, curate the directory, and manage announcements, reference data, and sync scoping. |

Most people are **viewers**. Editor and admin access is granted by a directory
administrator — editors are scoped to specific units. See the
[Administrator guide](/docs/admin/overview) for how those tools work.

## The directory dashboard is admin-only

The workspace dashboard at `/workspaces/…` is an **administrative** surface:
directory administrators use it, and non-admins don't see it. As a viewer or
editor, your home is **Find a Room**, not a workspace dashboard. (This is a
deliberate difference from the general ModelRails template, where the workspace
dashboard is user-facing.)

---

**Related:** [Finding a Room](/docs/user/finding-a-room) · [Administrator guide](/docs/admin/overview) · [Signing In](/docs/user/authentication)
