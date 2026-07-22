# MClassrooms Changelog

All notable changes to **MClassrooms** — the University of Michigan classroom
directory built on the [ModelRails](../CHANGELOG.md) template.

This file tracks the **fork's** product work. Template (ModelRails) changes that
arrive via upstream sync are recorded in [`CHANGELOG.md`](../CHANGELOG.md); this
file has no upstream counterpart, so the two never collide. Format follows
[Keep a Changelog](https://keepachangelog.com/); PR numbers are this repo
(`lsa-mis/mclassrooms_modelrails_wads`).

## [Unreleased]

The initial MClassrooms build (phases 0–5), targeting the first production
release — cutover to replace the legacy classroom directory. Availability
(phase 6), analytics (phase 7), and the cutover/ops integrations (phase 8) are
tracked separately and not yet included.

### Added

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

- CSP empty-nonce first-request bug that broke all JavaScript. (#26)
- Cookie-consent banner: two-mode, reject-emphasized banner with checkbox sync;
  reverted a banner flash. (#27, #28)

### Security

- Bumped **loofah 2.25.2** + **rails-html-sanitizer 1.7.1** for four sanitizer
  XSS advisories (Action Text / Lexxy path). (#48)

### Accessibility

- **WCAG 2.2 AAA gate** — suite-wide axe-core enforcement (cumulative tags, three
  custom checks, a 44px target-size floor) plus a full panel-review sweep: mobile
  layouts, dark-mode filter controls, contrast, tooltip/popover viewport
  clamping, and target sizes. (#20, #22, #31–#37)
