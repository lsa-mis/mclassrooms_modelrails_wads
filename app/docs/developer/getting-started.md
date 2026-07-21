---
title: Getting Started
description: Setup instructions and development workflow for ModelRails
keywords: setup install mise ruby bundle rspec tests oauth credentials development favicon icons branding ci lefthook git hooks accessibility
---

# Getting Started

## Prerequisites

- [mise](https://mise.jdx.dev/) for runtime version management (see `.tool-versions`)
- Chromium (managed automatically by Cuprite/Ferrum for system tests)

## Setup

```bash
mise install        # Install Ruby from .tool-versions
bin/setup           # Install deps, prepare database, start server
```

Or step by step:

```bash
bundle install
rails db:prepare
rails db:seed       # Seeds default roles
bin/dev             # Start development server
```

**Confirm it worked.** Once the server is up, open <http://localhost:3000> — you should see the public home page. That's a working install: nothing below (OAuth, a master key, `.env`) is required to get this far. `.env` is optional and only needed for production-style runs or Kamal — copy `.env.example` to `.env` if you reach for those (`bin/dev` does not need it).

### Ruby version as single source of truth

`.tool-versions` is the canonical pin for Ruby. It feeds three downstream consumers automatically:

| Consumer | Mechanism |
|---|---|
| **Local mise / asdf** | Reads `.tool-versions` directly when you `mise install` |
| **Bundler** | `Gemfile`'s `ruby file: ".tool-versions"` directive — Bundler refuses to install gems if the running Ruby doesn't match. `Gemfile.lock` captures it in the `RUBY VERSION` block. |
| **Production Docker image** | `Dockerfile`'s `ARG RUBY_VERSION` defaults to the same value; `config/deploy.yml` `builder.args.RUBY_VERSION` passes it to `kamal build` |

Bump Ruby in `.tool-versions`, run `bundle install`, and the lockfile + production builds all pick it up. If you ever break this invariant — e.g., editing `Dockerfile` `ARG` without `.tool-versions` — the integration spec at `spec/code_smells/template_invariants_spec.rb` fails with a specific actionable error.

### Dev Container (optional, VS Code)

This template ships a Dev Container configuration so you can develop in an isolated environment that matches production runtime closely. Open the project in VS Code and accept the "Reopen in Container" prompt, or run **Dev Containers: Rebuild Container** from the command palette.

The container is built on `ruby:4.0.6-slim` — the **same base image as the production `Dockerfile`** (Option C: shared base, separate files). That means libvips, glibc, SQLite, and OpenSSL versions all match prod. Bugs that depend on those library versions surface in dev rather than only in production.

Capabilities baked in:

- **`docker-outside-of-docker`** feature → `kamal deploy` works *from inside* the devcontainer (your machine's Docker daemon is exposed)
- **Named bundle cache volume** → gems survive container rebuilds; no 5-min reinstall on each rebuild
- **SSH agent forwarding** → `kamal deploy` SSHes to target hosts using your existing keys
- **Port forwarding** → `:3000` (Rails) labeled in VS Code's Ports panel; the dev mail inbox (Letter Opener Web) is at `/letter_opener` on that same URL

When the container first boots, `.devcontainer/setup.sh` invokes `bin/setup` (the canonical Rails setup script) plus installs system packages mirroring the production Dockerfile. It ends with explicit next-steps guidance — copy `.env.example`, run `bin/dev`, visit `localhost:3000`.

Native development (no devcontainer) continues to work the same way as before — `mise install`, `bin/setup`, `bin/dev`. The devcontainer is an addition, not a replacement.

## Choose your app preset

modelrails_base supports several distinct product shapes — solo prosumer, internal single-tenant, multi-tenant SaaS — all built on the same multi-tenant data layer underneath. Before you start customizing, read [App Presets](/docs/developer/presets) to identify which shape matches what you're building. The defaults you just installed are the **Solo-default** preset; additional presets ship as they're built.

## Running Tests

```bash
bin/parallel-rspec                       # Full suite across all cores (what CI and pre-push run)
bundle exec rspec spec/path/to_spec.rb   # Focused single-process run
bundle exec rspec --format documentation # Verbose output
```

`bin/parallel-rspec` splits the suite across your CPU cores (each worker gets
its own SQLite database and browser) and adds two integrity gates: the executed
example count must match a dry-run enumeration, and the merged coverage must
meet the 40% floor. Each run records per-file timings to
`tmp/parallel_runtime_rspec.log`, so the next run balances workers by measured
runtime instead of file size (it falls back to file size when the log is
absent). Coverage report is generated at `coverage/index.html`.

## Development Tools

These affordances only render in `Rails.env.development?` and are invisible in production.

### Preview sent emails (letter_opener)

The `letter_opener_web` engine is mounted at `/letter_opener` in development (`config/routes.rb`) and set as the mail delivery method. Every email sent in dev is captured and previewed in the browser instead of going out over SMTP.

Two ways to open the inbox:

- Visit `http://localhost:3000/letter_opener` directly
- On the `sessions/check_email.html.erb` page (reached after requesting a magic link), the "Check your email" heading is itself a clickable link to the inbox, opens in a new tab. Saves a URL round-trip while iterating on auth flows.

A dev-only CSP override at `config/initializers/letter_opener_web.rb` disables the app's content-security policy on the gem's controllers so its email preview iframe and inline scripts render. Safe because the engine is mounted only in development.

### Accessibility simulation drop-up

A dev-only widget in the footer cycles through visual-impairment filters applied to the whole page. Useful for spotting color-dependency issues, low-contrast problems, or layouts that fall apart without color.

**Modes:** Normal · Blur · Grayscale · Deuteranopia · Low contrast · Cataract

**Keyboard shortcuts** (active when the dropdown is open):

- `Cmd/Ctrl+Shift+A` — open or close the dropdown
- `0`–`5` — jump directly to a mode
- `Esc` or `Tab` — close the menu

State persists across reloads via `localStorage`. The filter is applied to `<body>` (so modals, toasts, and all Turbo-replaced content receive it). Deuteranopia uses an SVG color matrix (`<feColorMatrix>`); the others use CSS filters. A live region announces mode changes for screen-reader users.

**Source:** `app/views/shared/_a11y_sim.html.erb`, `app/javascript/controllers/a11y_sim_controller.js`.

### Cookie settings dispatch (how the footer button works)

Biscuit's gem normally renders a floating "Manage cookies" button in the bottom-left corner. The app hides that button via CSS and replaces it with an in-footer button that triggers the gem's reopen action through DOM click dispatch. See `app/javascript/controllers/footer_controller.js` and the Footer Structure section of `ui-patterns.md` for the full pattern.

## Key Commands

| Command | Purpose |
|---------|---------|
| `bin/dev` | Start development server |
| `bin/parallel-rspec` | Run full test suite in parallel (CI parity) |
| `bundle exec rspec` | Run focused specs single-process |
| `bundle exec brakeman` | Security scan |
| `rails users:unlock[email]` | Unlock a locked account |
| `rails users:verify[email]` | Manually verify an email |
| `rails users:suspend[email]` | Suspend a user |

## CI and Git Hooks

The project uses a two-gate CI pipeline:

### Gate 1: Local (Lefthook pre-push)

Runs automatically when you `git push`. No setup needed beyond `bundle exec lefthook install` (runs once after clone).

| Check | Tool |
|-------|------|
| Security scan | Brakeman |
| Full test suite | RSpec (full suite) |
| Accessibility audit | axe-core WCAG 2.2 AAA on every system spec |
| Code style | RuboCop |

Pre-commit hooks also auto-fix Ruby style issues on staged files.

Skip hooks in emergencies with `LEFTHOOK=0 git push` or `--no-verify`.

### Gate 2: GitHub Actions (on push/PR)

Runs the same checks plus additional linting:

| Job | What it checks |
|-----|---------------|
| `scan_ruby` | Brakeman + bundler-audit (gem CVEs) |
| `scan_js` | importmap audit (JS dependency CVEs) |
| `lint` | RuboCop with GitHub annotations |
| `lint_docs` | markdownlint + herb ERB linter |
| `test` | Full RSpec with Cuprite, axe accessibility, screenshot artifacts on failure |
| `docker_build` | Verifies the production `Dockerfile` builds successfully on every PR (catches build-time regressions that structural specs cannot). Uses GHA layer caching — cold builds ~3-5 min, warm builds ~30-60s. See [Deployment](/docs/developer/deployment). |

### Development Workflow

1. Create a feature branch: `git checkout -b my-feature`
2. Write tests, implement, verify locally: `bin/parallel-rspec`
3. Commit (pre-commit hook auto-fixes Ruby style)
4. Push (pre-push hook runs full CI locally)
5. Open PR on GitHub (Actions run second round of checks)

### Linting Commands

```bash
bundle exec rubocop                    # Check Ruby style
bundle exec rubocop --autocorrect-all  # Auto-fix Ruby style
bundle exec rake markdown:check        # Check markdown
bundle exec rake markdown:lint         # Auto-fix + check markdown
bundle exec rake erb:check             # Check ERB templates
```

## Favicon and PWA Icons

The app ships with a multi-format favicon setup in `public/`:

| File | Purpose |
|------|---------|
| `favicon.ico` | Legacy browsers (any size) |
| `icon.svg` | Modern browsers (scalable, crisp at all sizes) |
| `apple-touch-icon.png` | iOS home screen bookmark |
| `icon-192.png` | PWA icon (192x192) |
| `icon-512.png` | PWA icon and splash screen (512x512) |
| `manifest.webmanifest` | PWA manifest (app name, icons, theme) |

These are referenced in both `app/views/layouts/application.html.erb` and `app/views/layouts/markdowndocs/application.html.erb` via link tags in `<head>`.

To replace with your own branding, swap the files in `public/` keeping the same filenames and sizes. Update `name` and `short_name` in `manifest.webmanifest` to match your app name.

## OAuth Setup (optional)

Email/password and magic-link sign-in work without this — set up OAuth only if you want Google/GitHub sign-in. Add credentials for Google and GitHub OAuth (per-environment; the template ships no credential files, and the first run generates the blob and key):

```bash
bin/rails credentials:edit --environment development
```

```yaml
google:
  client_id: your_id
  client_secret: your_secret
github:
  client_id: your_id
  client_secret: your_secret
```

## Next steps

1. **[Choose your app shape →](/docs/developer/presets)** — Solo, Single-tenant, or Open SaaS. This is the most important decision; it sets signup, onboarding, and workspace behavior.
2. **[Extend the framework →](/docs/developer/extending)** — add your own workspace-scoped models, authorization, and features.
