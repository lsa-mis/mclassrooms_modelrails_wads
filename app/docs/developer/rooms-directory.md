---
title: Rooms directory
description: How the Find-a-Room and room pages work — search, live filtering, media stage, and every curation lever
keywords: rooms search filters characteristics curation filterable category_override panorama turbo frame announcer taxonomy
---

# Rooms directory

The fork's core surfaces: `/find-a-room` (RoomsController#index) and room
pages (#show). This doc covers the moving parts and — most usefully — the
**curation levers**, since much of the product's shape is data, not code.

## Search and live filtering

`RoomSearch` (`app/lib/room_search.rb`) is the query object. The form's
single `q` param matches building names OR rooms (FTS, facility code,
nickname) — the union. Legacy `building`/`room` params still work for old
URLs. Characteristic filters use AND semantics via
`Room.with_all_characteristics`.

The filter form lives **outside** the results Turbo Frame so typing never
loses focus; every change re-renders only `#find_a_room_results`
(`turbo_action: advance` keeps URLs shareable). Three patterns to preserve:

- **The announcer.** A persistent `#results_announcer` (aria-live, outside
  the frame) is written with the fresh count by `filter_form_controller`
  after each frame render — a live region *inside* a replaced frame is not
  reliably announced. Don't move the count announcement back into the frame.
- **State-changing links are `_top` full visits** (chips, Clear filters,
  admin view nav): a frame swap can't update the out-of-frame form's inputs
  and destroys keyboard focus.
- The in-frame **sort select** submits the form via its `form=` attribute;
  the `filter-form` Stimulus controller sits on a wrapper around form AND
  frame so those actions survive re-renders.

## The media stage (room page)

Panorama and photos are `UI::Tabs` panels — **hidden, never removed** — and
the Pannellum container carries `data-turbo-permanent`. A DOM swap or morph
over the booted WebGL viewer destroys the context and re-downloads the
panorama (~MBs); keep pane switching as show/hide forever. The panorama is
click-to-load by design, and the pre-load image is the flat rectilinear
render (`Room#flat_panorama`, see "Flat panorama renders" below) — the same
camera Pannellum boots at, so clicking Load produces no visual jump. Rooms
without media render `_media_empty_band` — a short branded band, never a
hero-height placeholder.

A room whose flat render has not landed yet (or can never land — a
non-equirectangular source) falls back to the old squashed-equirect `:poster`
named variant on `Room#panorama`. That fallback path — and the `:poster`
variant itself — is scheduled for deletion in a follow-up once the backfill
is complete everywhere; the ingest task no longer references `:poster` at
all.

### Bulk media ingest

`bin/rails panoramas:ingest DIR=/path/to/panos` loads a directory of
`<rmrecnbr>.jpg` files (the mi_locations export) onto matching rooms in the
shared workspace (`WORKSPACE=` overrides; `DRY_RUN=1` reports without
attaching; `REPLACE=1` re-attaches over existing panoramas — default is
skip, so re-runs are idempotent). Ingest pre-processes nothing itself — the
Active Storage attachment callback
(`config/initializers/flat_panorama_callbacks.rb`) enqueues
`RenderFlatPanoramaJob`, which renders the flat view the pano pane serves.
Two curation reports land in `tmp/panorama_ingest/`: files with
no matching room, and listed classrooms still lacking a panorama. Logic
lives in `PanoramaIngest` (`app/lib`); per-file failures collect into the
result without stopping the run.

### Flat panorama renders

Every panorama attach or replace enqueues `RenderFlatPanoramaJob`
(`config/initializers/flat_panorama_callbacks.rb` — read its header before
touching this lifecycle; it explains why the callback lives on
`ActiveStorage::Attachment` and not on `Room`). The job reprojects the
equirectangular source to the rectilinear view at Pannellum's default camera
and attaches it as `Room#flat_panorama`; the room page serves it as the
pre-load image until a visitor clicks Load. `lib/tasks/flat_panoramas.rake`
is the operator surface on top of that:

- `bin/rails panoramas:render_flat` — backfill every room with a missing or
  stale flat render. Flags: `DRY_RUN=1` reports without touching anything;
  `ROOM=<rmrecnbr>` scopes to one room; `FORCE=1` clears any tombstone and
  re-renders even an already-fresh room (the diagnostic loop after a
  projection code change); `INLINE=1` renders in-process instead of
  enqueueing — it does not wait on the queue, and a retryable error
  (`Vips::Error`, a SQLite statement timeout) still schedules a background
  retry rather than failing outright; `LIMIT=n` caps the batch;
  `WORKSPACE=slug` overrides the shared workspace.
- `bin/rails panoramas:flat_status` — read-only counts (with panorama,
  missing/stale, failed render, orphaned flat) for a workspace, plus the
  first ten failed rooms' stamped errors.
- A `flat_render_failed_at` tombstone, stamped on the SOURCE panorama blob's
  metadata, means the render failed permanently for that exact source (most
  often a non-2:1 photo uploaded into the panorama slot — see
  `Panorama::Rectilinear::NotEquirectangular`). It is keyed to the source
  blob, so replacing the bad photo clears it automatically; `FORCE=1` clears
  it manually without a replacement.
- On the room page, `#room_panorama_stage`'s `data-panorama-preview-source`
  attribute tells you which picture you're looking at, and why, without
  opening a console. Four values:
  - `flat_render` — the rectilinear render landed and matches the booted
    viewer. Nothing to do.
  - `flat_render_stale` — a render exists but does not match the recipe in
    force (someone changed `HFOV_DEG`/`ASPECT`/the default width without
    re-running the backfill), or its file is gone. It is still served — a
    stale frame beats a squashed strip — but the image **will** jump when the
    visitor clicks Load. Fix with `bin/rails panoramas:render_flat`.
  - `poster_fallback_failed` — no render, and the source carries a permanent
    failure tombstone. Read
    `room.panorama.blob.metadata["flat_render_error"]`; it is almost always a
    non-2:1 photo uploaded into the panorama slot, fixed by replacing the
    photo (which clears the tombstone by itself).
  - `poster_fallback` — no render yet, no failure recorded. Normal between a
    deploy and the backfill; `panoramas:flat_status` counts these.

  The staleness and tombstone questions have exactly one implementation each,
  `Room#flat_render_current?` and `Room#flat_render_failed?`, shared by this
  view, `RenderFlatPanoramaJob`, and both rake tasks.

`bin/rails building_photos:ingest DIR=/path/to/buildings` is the sibling
for building photos (`BuildingPhotoIngest`), with one difference: the files
carry display NAMES ("Mason_Hall.jpg"), so matching is tiered —
case-insensitive exact name, then a **unique** `Building.search_name` hit;
multiple hits are refused into an `ambiguous_files` report rather than
guessed (attach those by hand via the building edit form). Building photos
get `:hero` (building page) and `:thumb` (edit preview) named variants,
both eagerly processed; the building page serves `:hero`, never the raw
blob. Reports land in `tmp/building_photo_ingest/`.

## Curation levers (mostly data, not code)

| Lever | Mechanism | Effect |
|---|---|---|
| Filter vs informational | `CharacteristicDisplayRule#filterable` (admin UI) | `false` removes the checkbox from the filter panel; the room page and glossary still show it |
| Regrouping | `CharacteristicDisplayRule#category_override` | Moves a characteristic between filter/feature groups. Since the question-group pass, the override holds the **display-ready group name** ("Seats & layout", "Write on", "Show & present", "Recorded & accessible") and drives BOTH the filter panel and the room page's feature sections — un-overridden codes land in the room page's "More details" |
| Group order | `rooms.filters.group_order` (locale) | Panel groups render in this order; unlisted groups follow alphabetically |
| Renaming a characteristic | `rooms.characteristic_label_overrides` (locale) | Product-wide label ("Digital Data&Video" → "Projector") — vendor labels parse from sync descriptions and have no DB column, so locale is the rename mechanism (a deploy per rename; see backlog if that outgrows). With vendor legends gone, panel labels must be self-contained ("Power Outlets: Students" → "Power outlets at seats") |
| Renaming a group | `rooms.characteristic_group_overrides` (locale) | Fieldset legend names |
| Merged filter tokens | `RoomSearch::MERGED_CHARACTERISTICS` + locale label/description | One checkbox for one user question spanning several vendor codes ("Movable seating" = `movetablet ∪ tablesmov`; "Tiered or raked seating" = `floortier ∪ audseat`). ORs within members, ANDs against other selections; raw member codes in old URLs keep exact-match behavior; member codes never render their own checkboxes |
| Promoted chips | `RoomsHelper::PROMOTED_FILTER_CODES` | The always-visible "Popular features"; promoted codes are excluded from the panel (duplicate inputs double-submit). May name a merged token — the chip renders only when a member code exists in the data |
| Card tags | `RoomsHelper::CARD_TAG_CODES` + the filterable set | Cards only tag *distinctive* (filterable) characteristics — demoting a ubiquitous code also removes it from cards |
| Building names | `RoomsHelper::BUILDING_ACRONYMS` + `humanized_building_name` | ALL-CAPS vendor names are title-cased; acronyms keep caps; curated nicknames win |

Rule of thumb from the taxonomy work: **a filter is a question users ask; a
fact is something they read.** A characteristic matching ~95% of rooms (or
almost none) filters nothing — demote it.

## Directory chrome

`PublicDirectoryChrome` (rooms, buildings, glossary controllers) suppresses
the workspace shell — these are viewer-facing pages; workspace nav is
member chrome. Tenancy is separate (`DirectoryScoped`): admin config screens
are directory-scoped but keep their chrome.

## Notes, alerts, contacts

Result cards show per-room note/alert counts from one grouped roots-only
query (`@note_stats`) — never render note bodies on the index (Action Text
N+1). Room-page contact cards render only present fields; an absent contact
record collapses to a single sentence.

## Known follow-ups

The planning repo's backlog (`planning/backlog/`) tracks the deferred items:
the structured applied-filters refactor, the manual assistive-technology
review protocol, label-overrides-to-database trigger, and building
short-name curation.
