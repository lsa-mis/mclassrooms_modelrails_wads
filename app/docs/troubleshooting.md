---
title: Troubleshooting
description: Recovery procedures for dev-environment issues that aren't caught by tests
keywords: troubleshooting stimulus controller assets clobber precompile importmap propshaft tailwind dark mode markdowndocs
audience: [guide, technical]
---

# Troubleshooting

Recovery procedures for environment-state issues. These are problems where the test suite passes but something is wrong at runtime in the browser or terminal.

## Stimulus controller silently fails to register

**Symptom**: You add `app/javascript/controllers/<name>_controller.js`, place `data-controller="<name>"` on an element, click it — nothing happens. No errors in the DevTools console. `Stimulus.controllers.map(c => c.identifier)` doesn't include your new controller.

**Root cause**: A stale `public/assets/.manifest.json` from a past `bin/rails assets:precompile` run is making Propshaft prefer the static manifest over dynamic resolution. Files added after that precompile aren't in the manifest, so `helper.path_to_asset(...)` returns `nil` for them. Importmap-rails uses `filter_map` with `next unless resolved_path` when serializing the importmap, so those entries are silently dropped — no warning, no error, just a missing controller.

**Fix**:

```bash
bin/rails assets:clobber   # removes public/assets/ and the static manifest
# Ctrl-C the running bin/dev, then restart it
bin/dev
```

Then hard-reload the browser (Cmd-Shift-R). Verify with `Stimulus.controllers.map(c => c.identifier)` in the DevTools console — your controller should now be listed.

**Prevention**: `bin/setup` runs `assets:clobber` automatically, so a fresh setup invocation cures this. Don't run `bin/rails assets:precompile` locally except when deliberately testing the production-equivalent build (e.g., a Kamal smoke test); always clobber afterward.

## Tailwind classes from a gem template don't appear in compiled CSS

**Symptom**: A gem (e.g., markdowndocs) ships ERB templates with Tailwind classes like `dark:bg-slate-900`, but those utilities aren't generated into `app/assets/builds/tailwind.css` and the styling falls back to defaults.

**Root cause**: Tailwind only compiles utilities for classes it scans in source files referenced by `@source` directives. Gem template files installed under `~/.local/share/mise/installs/.../gems/<gem>-<version>/app/views/` aren't in the default scan path.

**Fix**: A `vendor/markdowndocs_views` symlink to the gem's view directory exists for exactly this reason — it gives Tailwind a stable, repo-relative scan target. The `@source` directive in `app/assets/tailwind/application.css` references it:

```css
@source "../../../vendor/markdowndocs_views/**/*.erb";
```

If a class from a gem template still isn't compiling, verify the symlink target points at the right gem version's view directory and re-run `bin/rails tailwindcss:build`.

## Dark mode applies to gem templates but the surface stays light

**Symptom**: `class="dark"` is on `<html>` and most of the app flips correctly, but a section rendered by an external gem (like markdowndocs `/docs/...`) keeps a light background while the text inside flips to light colors — making text invisible.

**Root cause**: The gem hardcodes Tailwind palette pairs like `bg-white dark:bg-slate-800` instead of going through the host's design tokens. CSS-variable-driven tokens (`--color-text-heading`, etc.) propagate via the cascade and flip wherever `.dark` is in scope, but the gem's literal `bg-white` utility wins specificity contests against `dark:bg-slate-800` in some Tailwind v4 cascade orderings, leaving the surface white while the inherited text color flips to its dark-mode value.

**Fix**: Override the gem's templates at `app/views/<engine_name>/...` using your design tokens (`bg-surface-raised`, `text-text-heading`, etc.). Rails view resolution prefers `app/views/` over engine view paths, so the host's overrides take precedence at render time. See the Markdowndocs Integration section of [architecture.md](/docs/architecture#markdowndocs-gem-integration) for how this is wired in this app.
