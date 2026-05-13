---
title: Getting Started
description: Setup instructions and development workflow for ModelRails
keywords: setup install mise ruby bundle rspec tests oauth credentials development favicon icons branding ci lefthook git hooks accessibility
audience: [guide, technical]
---

# Getting Started

## Prerequisites

- [mise](https://mise.jdx.dev/) for runtime version management (see `.tool-versions`)
- Chromium (installed by Playwright for system tests)

## Setup

```bash
mise install        # Install Ruby and Node from .tool-versions
bin/setup           # Install deps, prepare database, start server
```

Or step by step:

```bash
bundle install
rails db:prepare
rails db:seed       # Seeds default roles
bin/dev             # Start development server
```

## Running Tests

```bash
bundle exec rspec                        # Full suite
bundle exec rspec --format documentation # Verbose output
```

Coverage report is generated at `coverage/index.html`.

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
| `bundle exec rspec` | Run test suite |
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
| Full test suite | RSpec (566+ examples) |
| Accessibility audit | axe-core WCAG 2AA on every system spec |
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
| `test` | Full RSpec with Playwright, axe accessibility, screenshot artifacts on failure |

### Development Workflow

1. Create a feature branch: `git checkout -b my-feature`
2. Write tests, implement, verify locally: `bundle exec rspec`
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

## OAuth Setup

Add credentials for Google and GitHub OAuth:

```bash
bin/rails credentials:edit
```

```yaml
google:
  client_id: your_id
  client_secret: your_secret
github:
  client_id: your_id
  client_secret: your_secret
```
