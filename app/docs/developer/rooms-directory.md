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
- **The results header is sticky.** The frame opens with the live count,
  the removable filter chips, sort and the admin view nav, pinned while the
  cards scroll, so a filter change is visible where the results are. The
  frame's `[busy]` opacity utility is the pending state; Turbo sets and
  clears the attribute itself.
- **The announcement banner** is the shared `announcements/_banner`
  partial, also on the home and About pages; it renders nothing without an
  announcement.

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

## View and edit modes (room page)

`rooms/show` and `rooms/edit` both render `rooms/_page`, with `editing:`
false or true. View mode is the same page for every viewer, staff included,
plus an **Edit room** link for those who pass `RoomPolicy#edit?`. Edit mode
is `GET /rooms/:id/edit`: the same layout with the editing controls added.
Each partial swaps whole elements on `editing`; none opens a tag in one branch
and closes it in another, so the templates stay well-formed for an
HTML-aware ERB engine (Herb, in Rails 8.2).

- **One form, inputs in place.** `_page` renders an empty
  `form#room-edit-form`, which `PATCH`es `RoomsController#update`. The
  nickname and ADA seat count are built with `fields model:` and carry
  `form: "room-edit-form"`, so they can sit anywhere in the layout without
  wrapping the page in a `<form>`. That update takes only those two fields;
  a media or visibility param sent to it is dropped. The listing switch,
  media and note forms stay separate elements; nesting forms is invalid HTML.
- **Media editors.** In edit mode `_page` wraps the stage (or empty band)
  in a `media-dock` with `rooms/edit/_media_strip` fused to its top edge:
  a summary and, for admins, `rooms/edit/_panorama_editor` (`ui :dialog`)
  and `_gallery_editor` (`ui :dialog`); editors get the admin-managed note
  there instead. The strip sits outside the stage `<section>`, so its
  dialogs never nest inside the stage's own `modal` controller. The
  seating chart's `_seating_chart_editor` (`ui :dialog`) lives on its
  thumbnail in the documents card. All three are full-size dialogs that
  put a large preview (`_media_preview`, a `<label>` for the file input)
  beside the alt text and description. Each holds its own form, `PATCH`ing
  its own resource (`Rooms::PanoramasController`,
  `Rooms::SeatingChartsController` or `Rooms::GalleriesController#update`),
  with its submit button in the dialog footer pointed at the form by `form=`. **Upload new** is `ui :file_input` with `show_selection`
  behind a label (`_media_actions`) that shows "Upload new panorama" or
  "Upload new photo". The input's `aria-label` repeats those words and adds
  only the photo number (WCAG 2.5.3, Label in Name); it outranks the
  preview's own label, which would otherwise join the name. The preview
  image inside its label is `alt=""`, since its text is in the field beside
  it. Choosing a PNG, JPEG, WebP or GIF swaps the preview to an object URL
  (`media_preview_controller.js`) before anything is saved; a file it can't
  draw (PDF, HEIC) hides the preview rather than show the old image, and
  clearing the choice brings the saved image back.
  Replacing an existing photo's file counts as a change, and its
  `image_blob` is preloaded. A photo added from an empty add-photo row
  arrives through nested attributes with no workspace; `MediaAsset` copies
  its owner's `workspace_id` on create (ids only, so saving a gallery
  loads no workspaces), and an explicit mismatch is still rejected.
- **Media saves land in place.** A media dialog's successful save answers
  a Turbo request with `rooms/media/update.turbo_stream.erb`: it morphs
  `#room_media_strip` and `#room_documents` (their dialogs come back closed,
  with fresh previews and empty add-photo rows), replaces the contents of
  `#room_media_view` (a morph would strip the panorama viewer's
  client-built DOM), and appends "Panorama saved.", "Seating chart saved."
  or "Photos saved." as a toast. The page stays in edit mode at the same
  scroll position. When a morph would remove `open` from an open dialog,
  `modal_controller.js` cancels it and runs its own `close()`, so focus
  returns to the button that opened it. A morph keeps a file input's chosen
  file, so each editor form resets itself after a successful submit
  (`form_reset_controller.js`, on `turbo:submit-end`), and the preview
  restores from its image's `data-saved-src`, which the morph keeps current.
  Without Turbo the save redirects
  to `edit`. "Save room" still returns to the view page. `#edit`, the
  failure re-render and this response share `prepare_edit_page` (the
  `RoomEditPage` concern), and `RoomPresenter#stage_photos` is the one
  definition of the stage's photos. The stream template lists its regions
  by hand; a reactive template engine (ReActionView) that re-renders the
  page itself would replace it.
- **Removal is RESTful.** Each **Remove** is a submit button pointed by
  `form=` at its own small `DELETE` form, rendered after the main one so no
  form nests: `Rooms::PanoramasController`, `Rooms::SeatingChartsController`
  and `Rooms::PhotosController#destroy`, nested under rooms and sharing
  `Rooms::MediaController`. Each authorizes `manage_media?`, writes through
  `Curation::Apply` (`room.media_updated`), and redirects to
  `edit?open=<editor>`. `#edit` reopens that dialog, and its `description:`
  carries the flash, the alert when removal failed and the notice
  ("Photo 2 removed.") when it worked (`RoomsHelper#media_editor_message`):
  a toast outside an open modal is ignored by the accessibility tree
  (`activeModalDialog`), so the message must live in the dialog. A photo is
  numbered by its row in the editor, `Room#gallery_by_position` (position,
  then id), never by its stored `position`, which can have gaps and ties. The
  floor plan is `resource :floor_plan` (`Rooms::FloorPlansController`);
  nested controllers find their room through the `RoomScoped` concern.
- **Floor plan page** (`Rooms::FloorPlansController#show`). It lists the
  floor's classrooms in `Room.natural_room_order`, the same order Find a
  Room uses. The current room is marked with a visible badge and
  `aria-current="true"` (not `"page"`, since its link goes to the room, not
  this page). A PDF plan renders as a link, not an `<img>`.
- **Focus.** `modal_controller.js` returns focus to the opener, or to the
  dialog's own visible trigger (the gallery slide, or the editor button)
  when the opener is gone or the dialog was opened by the server, then to
  `<main tabindex="-1">`.
- **Stage permanence.** The panorama stage keeps a fixed id and
  `data-turbo-permanent` on the view page only (`permanent: false` in edit
  mode). Turbo therefore never carries the edit page's stage over to the
  view page, so a replaced panorama shows on save while the view page
  still keeps its booted viewer across refreshes.
- **Visibility is its own resource.** The listing switch sits in its own
  small form (`rooms/_visibility`): `POST /rooms/:id/hiding` hides the room
  and `DELETE` lists it again (`Rooms::HidingsController`), authorized with
  `hide?` and `unhide?`, so an editor's one-way hide holds against a crafted
  request. `Room#hide!`/`#unhide!` write their own audit rows. Toggling the
  switch saves at once: `room_visibility_controller.js` asks the hide
  confirmation first and puts the switch back if it is declined, and the
  Turbo answer morphs the switch (focus stays on it), refreshes
  `#room_media_view` for the hidden overlay, and appends a toast. Nothing
  navigates, so an unsaved nickname edit survives the toggle. An editor who
  hides a room is redirected to Find a Room, as they can no longer see it.
  Buildings use the same shape (`Buildings::HidingsController`). The switch
  is the curator's flag only: `Room.listed` also needs `in_feed`, so for a
  room the sync has dropped, the switch carries a description saying Find a
  Room won't list it until it returns.
- **Failure re-render.** A failed save renders `edit` with a 422. The page
  draws from a freshly loaded copy of the room (`@display_room`), because
  the failed record can hold an unsaved attachment that can't be previewed.
  Its forms bind to the failed record, so values and errors survive.
  `@open_media` reopens the dialog that was submitted; each media controller
  passes its own slot.
- **Notes.** The composer renders only in edit mode (`notes/_list`'s
  `editing:` local; the building page keeps the default). A note's Edit,
  Delete and Reply controls still render by policy, because Turbo broadcasts
  render `notes/_note` once for every subscriber. The room page hides them in
  view mode with `group-data-[room-mode=view]/room:hidden`, keyed to
  `data-room-mode` on the page root.
- **Hidden rooms.** `rooms/_hidden_overlay` lays the `hidden-hatch` utility
  and a warning pill over the media stage or empty band. Only admins can
  reach a hidden room, so only they see it.

### Who may save what

`RoomsController#update` permits only `CURATED_PARAMS` (nickname, ADA seat
count), which `RoomPolicy#update?` opens to the room's unit editor. Each
media resource authorizes `manage_media?` (admins) and permits only its own
slot's fields, so the media gate is the policy check on the resource, not a
branch in strong params. The `*_derived_ok` columns are retired: not
editable, not permitted, and ignored by `Describable#alt_status_for`, so an
image without authored alt text counts as needs-review on
`media:alt_coverage`, whatever an old flag says. `gallery_attributes` uses the
double-array `[[ ... ]]` shape `params.expect` needs for a hash of nested
rows: the single-array shape silently permits nothing, which would break
every gallery add, reorder and delete. The media editors resubmit the
metadata fields on every save, so `media_change?` compares each one with the
room's current value (`to_s` on both sides, so nil and "" match) rather than
testing for presence, and a save that changes nothing writes no audit row.

The gallery save checks every submitted row `id` against the room's own
gallery first. A row naming another room's photo, or one deleted since the
page loaded, would otherwise raise `RecordNotFound` inside
`assign_attributes`, before `Curation::Apply`'s transaction opens, and the
app-wide handler would bounce the editor off the page instead of re-rendering
the photos dialog with the stale-row error. It then preloads the attachments
of the rows it will validate, and only those: `with_attached_image` or an
unscoped preload trips Bullet's unused-eager-load check.
`BuildingsController#update` follows the same two rules for floors
(`stale_floor_ids?`, then a preload limited to floors receiving a new plan),
and saves the building's fields, photo and floor plans in one
`Curation::Apply` transaction (`building.curated`). Only a floor receiving a
new plan is validated on save; `remove_plan` alone never marks a floor
changed, so preloading it would be an unused eager load. The preload covers
`plan_blob` as well as `plan_attachment: :blob`, because the content-type
validator reads the blob through that shortcut, which Bullet tracks
separately. The building form takes no address fields and no visibility
params: the nightly sync owns the address, so an admin's edit would be
overwritten (or would overwrite sync data), and hiding is
`Buildings::HidingsController`.

## Lookups, scopes and caching

- **Finding the room.** `set_room` looks a room up by `rmrecnbr` (its
  `to_param`) through `for_current_workspace`, and deliberately does not
  filter `listed`: an admin must reach a hidden room to edit or unhide it,
  and the inactive redirect needs the record to decide. An unknown or
  other-workspace room number lands on Find a Room with "room not found",
  not on the app-wide not-found redirect to the home page.
- **Hidden rooms for non-admins.** `redirect_inactive_for_non_admins` runs
  on `show` only. A non-admin never reaches `edit` or `update` for a hidden
  room, because `RoomPolicy#edit?`/`#update?` already require it visible, so
  adding the redirect there would only block admins.
- **Inactive views.** Find a Room's `view=inactive_rooms` and
  `view=inactive_buildings` authorize `view_inactive?` first, then build
  `RoomPolicy::Scope#resolve_including_inactive` directly: Pundit's
  `policy_scope` only ever calls `resolve`. A viewer asking for either view is
  refused rather than quietly shown the active list.
- **Old search links.** `building` and `room` stay permitted search params
  beside the merged `q` box, because links shared before the redesign still
  use them.
- **Conditional GET (D14).** `show` answers 304 when nothing it renders has
  changed, and keeps Rails' default `Cache-Control: private, max-age=0,
  must-revalidate`; the legacy app's `no-store` is deliberately not set. The
  ETag covers the room, its contact record (which can change without the
  room's `updated_at`), whether the viewer is an admin and their saved-room
  state (both change what the page shows), and the newest notes on the room
  and its building. Attachments count through `created_at`, the newest
  across the room's own slots and its gallery photos:
  `active_storage_attachments` has no `updated_at`, because attaching makes a
  new row. The gallery half matches `record_type: MediaAsset.name`, not a
  string, because a mismatch fails silently as an ETag that never changes.
  The JSON branch preloads gallery attachments inside the fresh-response
  branch only, so a 304 carries no unused eager load.

## Landing and denials

- **Where sign-in lands.** The fork overrides the template's
  `authenticated_home_path` seam: a signed-in non-admin starts on Find a
  Room, decided once at sign-in, and admins keep the home page. Root itself
  never redirects, because the logo links there and a link named for the
  site must mean the same thing for every role. The check is the same one
  `DirectoryScoped` applies to Find a Room (a shared workspace that exists
  and isn't suspended), so a broken posture falls back to the home page
  instead of chaining redirects.
- **Where a refused request lands** (`ApplicationController#not_authorized_redirect_path`).
  Every branch has to be loop-safe. The workspace page is used only when
  `WorkspacePolicy#show?` allows it, which under the shared posture means
  admins, and never when the refused request was the workspace's own path
  (#931: GET, PATCH, PUT and DELETE share `/workspaces/:slug`). Otherwise a
  viewer goes to Find a Room, which needs a viewer grant, and anyone else to
  the home page, which never redirects. Outside a workspace the referer is
  used only through `url_from` (SEC-10), so a forged cross-origin referer
  falls back to the home page instead of raising `UnsafeRedirectError`.

## Public pages

`PagesController#show` serves the home, About, Privacy and Contact pages, as `page_path(:about)` and so on. The four pages render for everyone, signed in or not: the header logo links to the home page, and a link named for the site must mean the same thing for every role. Where a signed-in user starts is decided once, at sign-in (`ApplicationController#authenticated_home_path`). The home and About pages each show their announcement slot (`home_page`, `about_page`) through `announcements/_banner`; signed-in visitors see Find-a-Room calls to action where anonymous ones see sign-in.

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
