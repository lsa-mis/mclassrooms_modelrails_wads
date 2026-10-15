---
title: Administrator Guide
description: Curating the classroom directory — roles, room editing, visibility, notes, and the admin console
keywords: admin administrator editor curation hide unhide bulk upload announcements editor assignments characteristic display rules unit display names sync scope reference data
---

# Administrator Guide

MClassrooms is a **curated directory**: automated syncs keep the underlying room
data fresh, and **administrators** and **unit editors** layer curated content —
photos, descriptions, notes, and visibility decisions — on top. This guide covers
those tools. For how roles look from a user's perspective, see
[Roles & Access](/docs/user/workspaces).

## Who can do what

- **Admins** (directory administrators) can do everything, across every unit.
- **Editors** are scoped to one or more **units** (department groups). They can
  edit the rooms in their assigned units — but not rooms outside them, and not
  the admin-only actions below.
- **Viewers** — everyone else — browse the directory but change nothing.

Access is derived from your U-M identity on every request; there's nothing to set
up per session.

## Curating a room

A room's page looks the same to you as it does to everyone else: no note
composer, no hide button, no curation controls. The one difference is an
**Edit room** button.

**Edit room** keeps you on the same page and layout and adds the editing
controls in place:

- **Room details** sit under the photos: the nickname and the ADA seat count.
  The total seat count, room features and contacts sync nightly from U-M
  Facilities, so they're shown but not editable.
- **Listed in Find a Room** is a switch in the bar at the top, next to
  **Cancel** and **Save changes**. The bar stays in view while you scroll.
- **Notes** gain the composer and their Edit, Delete and Reply controls.

**Save changes** applies the nickname, the ADA count and the listing switch
together. Notes post on their own, and media saves from its own dialog.

What you can change depends on your role:

| Capability | Editor (own units) | Admin |
|------------|:------------------:|:-----:|
| Nickname and ADA seat count | yes | yes |
| Notes & alerts | yes | yes |
| Hide a room (one-way) | yes | yes |
| Unhide a room | — | yes |
| Photos, 360° panorama, seating chart, gallery | — | yes |
| Edit rooms in any unit | — | yes |

Every curated change is written to an **audit trail** with a before/after record
of exactly what changed.

### Adding media

In edit mode, admins get **Edit panorama** (or **Add panorama**) and
**Manage photos** (or **Add photos**) under the photos, and an editable
seating-chart thumbnail in the **Plans & documents** card. The panorama and
the seating chart each open a dialog with a preview, **Upload a new file**, a
remove option, and the alt text and description; **Save & apply** saves just
that item. **Manage photos** opens a side panel for the ordered gallery.
Editors see a note that media is managed by administrators, and flag problems
with a note instead.

Attachments are capped at 10 MB; images are PNG / JPEG / WebP / HEIC, and
PDFs are allowed only for seating charts and floor plans. For batches, use
**Bulk uploads** below.

## Visibility (hide / unhide)

Rooms and buildings can be hidden from the public directory. For a room, use
the **Listed in Find a Room** switch in edit mode and **Save changes**:

- **Hiding is one-way for editors.** An editor can hide a room in their unit (say,
  one that's out of service), but only an **admin** can bring it back — a hidden
  room can't be quietly un-hidden. Saving asks the editor to confirm, and the
  room then leaves their view entirely.
- **Admins hide and unhide** both rooms and buildings. A hidden room shows
  admins a hatched **Hidden · not listed in Find a Room** overlay across its
  photos.
- **Seeing hidden inventory.** Admins get **Listed / Hidden rooms / Hidden
  buildings** views (beside the sort control on Find a Room, and a "show hidden"
  toggle on the buildings index), with a banner whenever you're viewing hidden
  inventory. Non-admins never see hidden rooms or buildings anywhere — including
  by direct link.

## Notes & alerts

Admins and editors can attach **notes** to a room or building. Mark a note as an
**alert** to surface it prominently — a highlighted badge on result cards and the
room page. Notes support one level of replies, and like every curated change they
are audited.

## The admin console

The admin console (`/admin/…`) has six screens:

| Screen | What it's for |
|--------|---------------|
| **Announcements** | Post a banner in one of three slots — the home page, Find a Room, or the About page. One announcement per slot. |
| **Bulk uploads** | Drop a batch of room photos / panoramas / seating charts; MClassrooms matches each file to a room by its facility-code filename, shows matched vs. unmatched, and you commit the matched set. |
| **Editor assignments** | Grant or revoke a user's **editor** access, scoped to a specific unit. This is how you make someone an editor. |
| **Characteristic display rules** | Control how room characteristics appear — which show up as **filters** on Find a Room versus room-page information only, their grouping, and icons. |
| **Unit display names** | Override a raw department-group name with a friendlier display name. |
| **Sync scope rules** | Scope which campuses and buildings the nightly data sync includes or excludes. |

## Data sync

Room, building, characteristic, and contact data comes from U-M systems via an
automated **nightly sync** — you don't enter it by hand. Curated content (photos,
notes, display-name overrides, visibility) is layered on top and is **preserved
across syncs**. Use **Sync scope rules** to control which campuses and buildings
the sync covers.

---

**Related:** [Roles & Access](/docs/user/workspaces) · [Finding a Room](/docs/user/finding-a-room) · [Rooms directory (developer)](/docs/developer/rooms-directory)
