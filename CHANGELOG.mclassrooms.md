# MClassrooms Changelog

All notable changes to **MClassrooms** — the University of Michigan classroom
directory built on the
[ModelRails](https://github.com/dschmura/modelrails_base) template.

This file tracks the **fork's** product work. Template (ModelRails) changes that
arrive via upstream sync are recorded in [`CHANGELOG.md`](CHANGELOG.md); this
file has no upstream counterpart, so the two never collide. Format follows
[Keep a Changelog](https://keepachangelog.com/); PR numbers are this repo
(`lsa-mis/mclassrooms_modelrails_wads`).

## [Unreleased]

The initial MClassrooms build (phases 0–5), targeting the first production
release — cutover to replace the legacy classroom directory. Availability
(phase 6), analytics (phase 7), and the cutover/ops integrations (phase 8) are
tracked separately and not yet included. Work landing after that initial build
accumulates here too, newest first.

### Added

- **Flat panorama renders** — the room page's pre-load image is now a rectilinear
  render of the panorama matching the 360° viewer's camera exactly, instead of the
  raw equirectangular image squashed to 1024×512, so clicking **Load 360° view** no
  longer produces a visible jump. Stored as a derived Active Storage attachment
  (`Room#flat_panorama`) produced by a background job on panorama attach, with the
  previous `:poster` variant retained as a fallback so no room page breaks before
  the backfill runs. Ships with two operator tasks — `panoramas:render_flat`
  (`DRY_RUN` / `ROOM` / `FORCE` / `INLINE` / `LIMIT` / `WORKSPACE`) and
  `panoramas:flat_status` (missing / stale / failed / orphaned counts) — and a
  `data-panorama-preview-source` attribute on the stage, so "why does this room look
  wrong?" is answerable from devtools rather than a console. See
  `app/docs/developer/rooms-directory.md`. (#66)

- **Feedback path** — a support route that works before any external credentials
  exist. The [`lsa_tdx_feedback`](https://github.com/lsa-mis/lsa_feedback) gem's modal
  is rendered site-wide from the layout tail, reachable from a floating trigger
  (`FEEDBACK_FLOATING_TRIGGER=false` to disable) and a `/contact` CTA. Submissions go
  through a fork override of the gem's controller: **unauthenticated allowed** (so
  "I can't sign in" is reportable), IP rate-limited, then `Feedback::Submit` files a
  TeamDynamix ticket when `TDX_*` is configured and **emails the directory's admins
  otherwise or on any TDX error** — feedback never silently disappears. The page the
  user was on travels with the submission. Brought to WCAG 2.2 AAA in both themes via
  a fork override stylesheet, since the gem's own modal predates those gates.
  (#52, #53, #54, #55)
- **Legacy URL redirects** — the four retired Classroom Database URLs keep resolving
  after cutover, so old bookmarks, registrar links and deep links don't 404:
  `classrooms/:facility_code` → the room (case-insensitive; unknown → Find a Room with
  a notice), `classrooms` → Find a Room pre-filtered to LSA, `legacy_crdb` →
  `rooms.lsa.umich.edu`, and `toggle_visibile/:id` → the room's edit page, where
  hide/unhide now lives. Redirect-only and reachable signed out. (#50)
- **DB-backed image alt text and descriptions** for every image-bearing model,
  resolving stored-wins-else-derived so rendered `alt` is never empty and the AAA floor
  always holds, with a three-state review status (`authored` / `derived_ok` /
  `needs_review`), a `media:alt_coverage` report, and a CI ratchet. Built for the
  legacy media cutover, where imported images arrive with no authored alt — they degrade
  gracefully and can be worked down over time without fabricating metadata. (#62)
- **Production deployment config** — `config/deploy.yml` for the real service (GHCR
  image, kamal-proxy SSL, storage volume, shared/creation-disabled tenancy, SSO-only
  auth, U-M gateway sync), `.kamal/secrets`, and a fork-owned
  `app/docs/developer/deployment-miclassrooms.md` carrying the ENV inventory and go-live
  checklist. Ships with `REPLACE_WITH_*` placeholders for the values LSA TS must supply
  (hostname, server IP, Okta issuer/client-id, owner email) — a scaffold, deliberately
  not deployable as-is. (#51)
- **Administrator guide** (`app/docs/admin/overview.md`) — roles, the editor-vs-admin
  capability matrix, media, hide/unhide, notes and alerts, the six real admin console
  screens, and the nightly data sync. (#49)

- **Find a Room** — a live classroom directory: full-text search across building
  names and room numbers, five combinable filters (School/College, capacity
  **min–max range**, and grouped room characteristics), a "question"-grouped
  filter panel with an inline per-filter glossary, a live result count, shareable
  filtered URLs, and capacity/name sorting. (#5, #13, #15, #16, #23, #24, #25, #38–#45)
- **Room pages** — media-led detail pages: photo, 360° panorama, seating chart,
  gallery, and floor-plan views; grouped characteristics; a scheduling/support
  contacts rail; a native share sheet with clipboard fallback; natural-key
  (`rmrecnbr`) URLs. (#6, #30, #32, #33, #36)
- **Buildings** — viewer-visible building index and detail pages. (#46)
- **Saved rooms** — a personal shortlist with a saved-only view and a live count. (#14)
- **Curation & roles** — the admin / editor / viewer model (`RoleResolver` with
  per-unit editor assignments); one-way editor hide + admin unhide for rooms and
  buildings; notes & alerts; announcements (three banner slots); a transactional
  audit trail; and reference-data admin (characteristic display rules, unit
  display names, sync scope rules). (#7)
- **U-M data ingestion** — nightly sync of campuses, buildings, rooms, facility
  IDs, characteristics, and contacts from U-M gateway APIs, with dry-run, resume,
  and sync scoping; validated live against the real gateway. (#4, #9, #10, #12)
- **Media ingestion** — bulk panorama and building-photo importers with
  facility-code / tiered name matching and curation/refusal reports. (#18, #19)
- **Fork foundation** — shared-tenancy (single directory) posture, U-M SSO
  (Google + Okta), the viewer self-join role, token-gated test login, and the
  `RoleResolver` capability model; "logo means home" root routing. (#1, #2, #3, #8, #17)

### Changed

- **Room stills graduated to a first-class media model.** The single `Room#photo`
  slot and the `RoomGalleryImage` join are gone; rooms (and, by design, buildings
  and floors later) own an ordered gallery of polymorphic `MediaAsset` records —
  workspace-tenanted, positioned, and carrying the full authored-or-derived
  alt/description contract. Each asset can be tagged with **what it shows**
  (front, back, podium, rack, inner door, other), encoding the capture protocol:
  insertion order is the display rank, subjects retire rather than delete, and
  the shot number suggests the subject. Derived alt text is per-subject with
  positional disambiguation, fails loudly rather than interpolating a blank
  owner name, and is ratcheted by a spec that renders every consumer's real
  template against a blank. HEIC/HEIF — the phone camera default — is accepted
  on every room, building, and floor image slot, and **no display path serves
  an original blob**: the 360° viewer texture, seating-chart lightbox,
  floor-plan page, gallery lightbox (now truly full-size instead of an
  upscaled thumbnail), and the room and building JSON payloads all serve
  declared webp variants — the gallery's warmed off the request path on
  upload, the rest rendered on first request. The
  find-a-room thumbnail resolves through one presenter chain (flat render →
  poster → first ranked still) with the whole page preloaded to a pinned query
  budget. Bulk-dropped bare `CODE.jpg` files append gallery assets (duplicates
  visible and deletable in the coming editor) rather than silently replacing a
  photo.

- **Public wordmark standardized on MClassrooms** (no "i") everywhere user-facing —
  brand copy, home/about, `/docs` content and its category heading, the shared-workspace
  display name, and this changelog. Historical `# Phase N Task M` code comments are
  deliberately untouched. (#61)
- **Privacy page defers to U-M rather than inventing policy.** The template shipped
  generic SaaS boilerplate about how *ModelRails* handles your information. It now points
  at the [U-M Privacy Notice](https://umich.edu/about/privacy/) and SPG 601.41, and
  honestly discloses what the directory collects beyond a plain listing — verified against
  the code: SSO identity, session IP/browser and hashed device recognition, the admin
  audit log, cookies, and feedback routed to TeamDynamix. The legacy app took the same
  approach. (#61)
- **Contact page surfaces real support paths** — LSA Technology Services, the feedback
  modal, and per-room support contacts — replacing the open-source-template framing
  (`support@modelrails.dev`, "report bugs on GitHub", star-the-project). (#61)
- **User docs rewritten to describe this fork, not the template.** Several front-door
  `/docs` pages were giving users flatly wrong information: authentication documented
  passwordless magic links and GitHub as the primary path with Okta unmentioned (it is
  SSO-first, Google or Okta, account auto-created on first sign-in — magic links are the
  administrator break-glass path); `welcome` framed the app as the ModelRails template
  with "create or join a workspace"; `workspaces` described full multi-tenancy and is now
  "Roles & Access"; and Find a Room documented capacity as minimum-only when it is a
  min–max range. Those three repurposed pages joined the `merge=ours` fork seam. (#49)
- **Upstream syncs** from `modelrails_base_wads` — the cookie-consent Cancel affordance,
  random spec ordering, and dependency bumps (solid_queue, solid_cable, lexxy, pagy,
  markdowndocs, thruster, simplecov), plus i18n hardening: `raise_on_missing_translations`
  and an `i18n-tasks` gate that fails CI on missing keys or inconsistent interpolations.
  (#58, #64)
- The **workspace dashboard is admin-only** under the shared posture — non-admins
  can't reach `/workspaces/:slug` and land on Find a Room instead. (#47)
- The **building index is viewer-visible**, with admin controls (show-hidden,
  hide/unhide) gated within the page. (#46)
- **Find a Room filter IA** — School/College and the capacity range promoted under
  Search; humanized chip labels (registrar original in the tooltip); consistent
  filter styling; results-toolbar cleanup (honest count, pinned Clear filters). (#39–#45)
- **Upstream sync** from `modelrails_base` + Playwright→Cuprite system-spec
  migration; markdowndocs 0.11 / modelrails_ui 0.7 (shim removal). (#21, #29)

### Fixed

- **"Workspace not found" on every product page** in any environment whose shared
  workspace predated the brand rename. #61 changed the configured slug but never migrated
  existing rows, so `DirectoryScoped` resolved a slug no record had and Find a Room,
  Buildings — everything — redirected. An idempotent, collision-safe data migration aligns
  the rows; slugs are hardcoded in it as a historical fact, so a future rename gets its own
  migration instead of re-running this one. (#63)
- **Feature chips on the Find a Room cards now show their descriptions on hover.** The
  card's stretched title-link overlay sat above the emphasized chip strip and swallowed the
  pointer, so only the chips inside "+N more features" ever produced a popover. The strip
  now sits above the overlay on hover-capable pointers only — on touch, tapping a chip
  still opens the room, and keyboard access was never affected. (#65)
- **The floating feedback trigger no longer covers toast notifications.** At 375×667 it
  painted over roughly 51px of a warning toast's right edge — exactly where the dismiss
  button sits. Dropped just below the toast layer and tied to the same token so it tracks
  future changes; a persistent low-priority button should not obscure a transient error.
  (#56)
- CSP empty-nonce first-request bug that broke all JavaScript. (#26)
- Cookie-consent banner: two-mode, reject-emphasized banner with checkbox sync;
  reverted a banner flash. (#27, #28)

### Security

- **Rails 8.1.3.1** — CVE-2026-66066: Active Storage did not disable libvips'
  unfuzzed image loaders, so a crafted upload could read arbitrary server files including
  `secret_key_base`. Arrived with an initializer pruning BMP/ICO/PSD variant loaders. (#64)
- Bumped **loofah 2.25.2** + **rails-html-sanitizer 1.7.1** for four sanitizer
  XSS advisories (Action Text / Lexxy path). (#48, also carried in the #58 sync)

### Internal

- **System specs hardened against the Stimulus connection race.** Component preview specs
  interacted with a Stimulus-driven behavior immediately after `visit`; the importmap fetch
  and Stimulus boot lag behind the load event, so an event fired before the controller
  connects is silently dropped and the behavior never fires. Harmless while a warm spec
  always ran first — but random spec ordering (enabled in #58) can make an interactive spec
  the first to run against a cold module cache, exposing roughly 71 preview specs.
  `spec/support/stimulus_ready.rb` now blocks after preview navigation until every
  `data-controller` element has connected: one central fix, zero per-spec churn, and future
  component specs are covered for free. (#59, #60)
- **Feedback specs pinned against a local `.env` leak** — the "TDX not configured" examples
  assumed `valid?` was false but never forced it, so a developer with real `TDX_*` values
  set locally had dotenv leak them into the test env and the suite attempted a real HTTP
  call. Both paths now stub explicitly and are deterministic either way. (#57)
- **Two fork deviations recorded against the template's new gates**, both arriving with the
  upstream sync. `flash_messages_are_asserted_spec` requires every controller flash to be
  asserted by a spec, not merely redirected past; twelve fork-only admin flashes
  (`characteristic_display_rules`, `sync_scope_rules`, `unit_display_names`,
  `editor_assignments`, announcements) sit on its burn-down list because three of those
  controllers have no request spec at all — tracked as its own work. And
  `template_invariants_spec`'s "bin/fork's rename targets still exist" example is skipped
  here: it asserts the template still contains the `ModelRails` /
  `support@modelrails.dev` tokens that #61 deliberately removed from two `merge=ours`
  files, so it is a true invariant upstream and an impossible one downstream. The block's
  preset-parity examples stay active. (#69)

### Accessibility

- **WCAG 2.2 AAA gate** — suite-wide axe-core enforcement (cumulative tags, three
  custom checks, a 44px target-size floor) plus a full panel-review sweep: mobile
  layouts, dark-mode filter controls, contrast, tooltip/popover viewport
  clamping, and target sizes. (#20, #22, #31–#37)
