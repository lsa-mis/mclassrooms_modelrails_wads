# MClassrooms

The University of Michigan's classroom directory — find registrar-schedulable
classrooms on the Ann Arbor campus and see capacity, equipment, photos, and
floor plans before you teach or book.

Built on [ModelRails](https://github.com/dschmura/modelrails_base), a
multi-tenant SaaS starter kit for Rails 8.1. This app runs that template in its
**shared-directory** posture: one workspace, no workspace creation or switching,
and a role model of admin / editor / viewer rather than per-tenant accounts.

## What it does

- **Find a Room** — full-text search across building names and room numbers, with
  School/College, a capacity min–max range, and grouped room characteristics.
  Filtered URLs are shareable.
- **Room pages** — photo, 360° panorama, seating chart, gallery, and floor plan;
  grouped characteristics; scheduling and support contacts. Rooms are addressed by
  their registrar key (`rmrecnbr`).
- **Buildings** — index and detail pages.
- **Saved rooms** — a personal shortlist.
- **Curation** — editors (scoped to their unit) and admins maintain media, notes,
  alerts, announcements and visibility, over data synced nightly from U-M gateway
  APIs. Every curation write is audited.

## Tech stack

- **Framework:** Rails 8.1, Ruby 4.0.6
- **Database:** SQLite (Solid Queue/Cache/Cable in-process, single host)
- **Frontend:** TailwindCSS 4 with OKLCH semantic tokens, Turbo, Stimulus;
  `UI::*` ViewComponents from the vendored `modelrails_ui` gem
- **Assets:** Propshaft, importmaps
- **Auth:** U-M SSO — Google and Okta (OIDC). Magic links remain as an
  administrator break-glass path. Authorization via Pundit.
- **Content:** Action Text with [Lexxy](https://github.com/basecamp/lexxy)
- **Docs:** markdowndocs engine at `/docs`, content in `app/docs/`
- **Testing:** RSpec, FactoryBot, Capybara + Cuprite (pure-Ruby CDP — no Node),
  axe-core at WCAG 2.2 AAA, Bullet (N+1 detection)
- **Deployment:** Kamal → GitHub Container Registry; CI builds the production
  image on every PR
- **Version management:** [mise](https://mise.jdx.dev/) — `Gemfile` reads
  `.tool-versions`, so Bundler enforces the Ruby version everywhere
- **Dev container:** optional, on `ruby:4.0.6-slim` (production parity)

## Getting started

```bash
mise install     # Ruby and Node from .tool-versions
bin/setup        # dependencies, database, then start the server
```

Or step by step:

```bash
bundle install
bin/rails db:prepare
bin/dev
```

Fuller setup notes, including SSO configuration, live at
[`app/docs/developer/getting-started.md`](app/docs/developer/getting-started.md)
and render at `/docs` in the running app.

## Tests

```bash
bundle exec rspec          # single-process reference path
bin/parallel-rspec         # all cores, with example-count and coverage integrity gates
```

Coverage is written to `coverage/index.html`. System specs drive real Chromium
through Cuprite; accessibility is enforced in CI at AAA, not checked by hand.

## Documentation

Everything else lives in `app/docs/` and renders at `/docs`:

- **Users** — [finding a room](app/docs/user/finding-a-room.md), roles and access
- **Administrators** — [overview](app/docs/admin/overview.md): curation, media,
  visibility, the admin console screens, and the nightly sync
- **Developers** — architecture, the
  [rooms directory](app/docs/developer/rooms-directory.md), background jobs,
  security, and
  [deployment](app/docs/developer/deployment-miclassrooms.md)

## Changelog

- [`CHANGELOG.mclassrooms.md`](CHANGELOG.mclassrooms.md) — this app's changes.
- [`CHANGELOG.md`](CHANGELOG.md) — the ModelRails template's, arriving via
  upstream sync. Fork entries do not go there; it is not `merge=ours`, so they
  would become a merge conflict on every sync.

## Relationship to the template

This repo is a **fork**, not the template. Upstream improvements are merged in
periodically, and fork-owned files are protected by the `merge=ours` seam
(`README.md`, `_brand.css`, `config/routes/app.rb`, the fork's user docs, and
others). The contract, the identity-rename checklist, and the upstream-update
workflow are documented in
[`app/docs/developer/forking.md`](app/docs/developer/forking.md).
