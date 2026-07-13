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
click-to-load by design (static poster first). Rooms without media render
`_media_empty_band` — a short branded band, never a hero-height placeholder.

The poster is the `:poster` **named variant** on `Room#panorama`
(`resize_to_limit: [1024, 512]`, webp) — defined on the attachment so the
pano pane and the ingest task share one definition.

### Bulk media ingest

`bin/rails panoramas:ingest DIR=/path/to/panos` loads a directory of
`<rmrecnbr>.jpg` files (the mi_locations export) onto matching rooms in the
shared workspace (`WORKSPACE=` overrides; `DRY_RUN=1` reports without
attaching; `REPLACE=1` re-attaches over existing panoramas — default is
skip, so re-runs are idempotent). The `:poster` variant is **eagerly
processed at ingest** so the first visitor never waits on a multi-MB vips
transform. Two curation reports land in `tmp/panorama_ingest/`: files with
no matching room, and listed classrooms still lacking a panorama. Logic
lives in `PanoramaIngest` (`app/lib`); per-file failures collect into the
result without stopping the run.

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
