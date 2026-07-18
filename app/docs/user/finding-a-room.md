---
title: Finding a Room
description: Search, filter, and explore U-M classrooms — and read a room's full page
keywords: find a room search filters capacity characteristics panorama photos seating chart floor plan notes alerts
---

# Finding a Room

**Find a Room** (`/find-a-room`) is a live directory of listed classrooms.
Results update as you type or change any filter — the count under the filter
card always reflects what you'd get right now.

## Searching and filtering

- **Search** matches building names and room numbers in one box — "mason",
  "1300 chem", or a facility code like `mas1401` all work.
- **School / College** narrows to the classrooms owned by a department group.
  It's a primary facet, right under Search.
- **Capacity** is a **range** — set a minimum, a maximum, or both. Leave an end
  blank to leave it open; asking for more seats than any room has honestly
  returns "0 rooms found."
- **Popular features** are the most-asked-for characteristics, one click away.
- **More filters** opens the full set, grouped by the question you're asking
  (Seats & layout, Write on, Show & present, Recorded & accessible). Some
  filters bundle related setups — "Movable seating" matches tablet armchairs
  *or* tables with movable chairs; "Tiered or raked seating" covers sloped and
  stepped rooms. Hover or keyboard-focus any filter to see what it means in an
  inline popover — that's the glossary, right where you need it; a link to the
  full glossary sits in the card header. Applied filters from this panel show a
  count on the toggle.

Every applied filter appears as a removable chip beside the live count —
click a chip's × to drop just that filter, or **Clear filters** in the card
header to start over. The page URL always reflects your current search, so
you can bookmark or share a filtered view. Sorting (building/room order or
by capacity) lives with the results, next to the count.

## Result cards

Each card shows the room's name (click it to open the full room page), its
floor and school/college, the seat count with an ADA badge when the room has
ADA-accessible seating, and tags for its *distinctive* features. Rooms with
notes show a note count — and a highlighted badge when any note is an alert.
**Details** expands the full characteristic list; hover any chiclet for its
description.

## Saving rooms

Save a room to a personal shortlist with the **save toggle** on any result card
or room page. The **Saved rooms** link above the results filters the list to
just your saved rooms, with a live count that updates as you go. Your shortlist
is private to your account.

## Browsing buildings

Every building has its own page listing the classrooms it contains — reachable
from any room's page, or directly at `/buildings`. The buildings index shows the
buildings that have listed classrooms, so you can start from a building and work
down to a room.

## The room page

A room's own page leads with its media: the 360° panorama (press **Load 360°
view** to download and explore it — drag or use the arrow keys), with photos
on a second tab when both exist. Rooms without media show a simple banner
with the room's details instead.

Below the media: what the room supports (grouped characteristics), live
notes and alerts about the room and its building, and a rail with
scheduling/support contacts (only what's actually on file), seating chart
and floor plan links, and the building address. **Copy link** puts a
shareable summary on your clipboard. The "Find a Room" breadcrumb returns
you to the search you came from, filters intact.

## For administrators

Admins see extra controls gated within the same pages: **Listed / Hidden
rooms / Hidden buildings** views beside the sort control (with a banner
whenever you're viewing hidden inventory), an **Edit room** button on room
pages, an **Add photos** prompt on rooms without media, and note authoring.
Which characteristics appear as filters — versus room-page information
only — is curated in the admin's characteristic display rules; see the
developer doc [Rooms directory](/docs/developer/rooms-directory) for the
full set of curation levers.
