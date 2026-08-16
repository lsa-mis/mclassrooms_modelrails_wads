---
title: Testing
description: Suite architecture, testing conventions, and the guards that keep the suite honest
keywords: testing rspec parallel sharding coverage code smells i18n bullet cuprite ferrum cdp stimulus csp webauthn sqlite lock flaky system specs
---

# Testing

How the test suite is put together: the parallel runner and CI sharding, the convention-enforcing guard specs, the system-spec infrastructure, and the fail-fast guards that turn confusing whole-suite failures into one actionable message.

## Suite architecture

### Two ways to run the suite

- `bundle exec rspec` is the single-process reference path — always correct, just slow.
- `bin/parallel-rspec` is the full-suite path: it runs the suite across all cores via `parallel_tests`, with two integrity gates layered on top of pass/fail.

The two gates exist because a parallel splitter can silently drop work:

1. **Example-count parity.** A `--dry-run` enumeration fixes the expected example count before the run, and the per-worker counts must sum to exactly that number. The enumeration costs about 50 seconds per run — a deliberate price (#496) for "green means everything ran". It exists because the splitter really has dropped files; don't move it to a schedule or hide it behind a cache.
2. **Merged coverage floor.** Each worker sees only ~1/N of the suite, so workers skip the minimum-coverage check; `SimpleCov.collate` enforces the floor on the merged result instead.

Worker count comes from `PARALLEL_TEST_PROCESSORS` or the machine's core count.

### CI sharding

CI splits the suite across an 8-way shard matrix (#495, PR #615). With `CI_SHARD_INDEX` and `CI_SHARD_TOTAL` set, `bin/parallel-rspec` takes only its shard's slice of the spec files — greedy-packed by recorded per-file runtimes, with file size as the fallback weight — and skips the merged-coverage floor (each shard sees only a fraction of the suite; the `coverage_merge` CI job collates every shard's resultset and enforces the floor there). Example-count parity still runs per shard against the shard's own enumeration, and each shard records its file list so CI can assert the union of shards equals the full spec set — the shard splitter gets the same distrust as the worker splitter.

### The runtime log lifecycle

`bin/parallel-rspec` writes `tmp/parallel_runtime_rspec.log` — per-file spec timings. `parallel_tests` reads it on the *next* run to split work by measured time instead of file size, which evens out the slowest worker. That only helps if the log survives between CI runs, so it is cached (#488), and since sharding the lifecycle spans three jobs:

- `split_seed` snapshots one **frozen** copy of the log, downloaded by every shard — the cross-shard split must be computed from identical input or shards overlap and leave holes.
- `test_shard` restores the live log separately to seed *in-shard* worker balancing.
- `coverage_merge` reassembles every shard's partial log and saves the cache for the next run.

A cache miss is harmless: the split falls back to file size — still correct, just less balanced.

## Conventions and guards

### The code-smells suite

`spec/code_smells/` holds specs that enforce project conventions structurally rather than by review. Examples: `mutating_actions_are_authorized_spec.rb` fails if a POST/PATCH/PUT/DELETE action neither calls `authorize` nor sits on the reviewed allow-list, and `no_unscoped_tenant_loads_spec.rb` fails on unscoped tenant finders in controllers (see [Extending](/docs/developer/extending)).

The largest member is `spec/code_smells/template_invariants_spec.rb`. ModelRails is a template meant to be forked, so every default it ships propagates into every downstream fork; this spec asserts the structural invariants that came out of an 8-reviewer panel review on 2026-05-18. Each one catches a class of subtle misconfiguration that would otherwise propagate silently — Ruby-version drift across `.tool-versions`, `Gemfile`, `Gemfile.lock`, and the `Dockerfile`; test gems leaking into the production image; Dockerfile layer-cache invalidation from COPY ordering; dev/prod base-image divergence; missing onboarding signals; unused free performance settings — plus invariants added since, such as the vulnerability-scan rules below.

One of those is worth understanding when a CI change makes it fire: the container vulnerability scan must **never** reuse the Docker layer cache (#536). GitHub Actions cache scoping makes a branch read its *own* cache scope first, so a PR replays its own stale apt layer and never sees the fix main already picked up — stale-package CVE findings then look identical to real ones. Rebuilding costs about 45 seconds per run, which is cheap for a red that always means what it says.

### The two i18n gates

Two complementary gates cover missing translations, and it is worth being precise about which covers what:

- **`config.i18n.raise_on_missing_translations`** (in `config/environments/test.rb`) catches a missing key at runtime — but only on a code path some spec actually walks, and only when the call site has no inline `default:` to swallow it. Since `available_locales` is pinned to `[:en]`, this raise only ever exercises the base locale.
- **`spec/i18n_spec.rb`** (backed by i18n-tasks) is the static counterpart: it catches missing keys repo-wide without executing anything, including cross-locale gaps once a fork adds a locale. It also fails on inconsistent interpolations and on **unused keys** (#522 — 120 orphans were cleared when that gate landed). Delete unused keys, or add them to `ignore_unused` in `config/i18n-tasks.yml` with a reason when the consumer is dynamic or lives in a scanner-excluded path.

`config.i18n.fallbacks` mirrors production so a lookup reaching a non-base locale terminates at `:en` rather than dying — a key missing from `:en` still raises, which is the point.

### Bullet safelists live in one file

Bullet raises on N+1 queries in test and alerts in development. Its safelists — intentional preload and delivery-layer trade-offs that hold in both environments, since the app code is identical — are centralized in `lib/bullet_safelists.rb` rather than duplicated per environment file. They drifted once: `development.rb` carried only two entries while `test.rb` had the full set, so false positives fired in dev but never in test, invisible to the suite. One source removes that whole class of drift. Each environment file keeps its own enable/display/raise configuration and calls `BulletSafelists.apply` after `Bullet.enable = true`; every safelist entry carries a comment explaining the trade-off it encodes.

## System-spec infrastructure

System specs run on Capybara + Cuprite, a pure-Ruby CDP driver (the suite migrated off Playwright in #497 — no Node dependency). The support files below make that stack reliable.

### CDP helpers

`spec/support/cdp_helpers.rb` wraps the Ferrum/CDP operations the specs need — Cuprite exposes the underlying `Ferrum::Browser` at `page.driver.browser`. The helpers came out of the Playwright→Ferrum migration (#497): `cdp_evaluate` / `cdp_evaluate_async` / `cdp_execute` for JS, `cdp_add_init_script` (call before visiting), `cdp_press`, `cdp_click_at`, `cdp_clear_cookies`, `cdp_resize`, `cdp_emulate_reduced_motion`, `cdp_intercept`, and raw `cdp_command` — each documented at its definition. Two gotchas the helpers encode: Ferrum's `evaluate` wraps source in a returning function, which breaks UMD bundles like axe-core (`cdp_execute` runs the raw statement instead), and network interception has no per-route handler — every intercepted request **must** call `.continue`, `.abort`, or `.respond`, or Ferrum leaves it hanging.

### Stimulus readiness gate

The importmap module fetch and Stimulus boot lag behind page load, so an event dispatched before a controller connects is silently dropped. That is harmless while a warm spec always runs first, but random spec ordering can make an interactive spec the *first* to run against a cold module cache — an intermittent failure. Rather than sprinkle waits across specs, `spec/support/stimulus_ready.rb` waits once, centrally: after any system-spec `visit` to a Lookbook component preview (`/rails/view_components/`) or the form-drafts harness (`/draft_harness`, #525 — a flake that survived every local run and failed CI precisely because the gate didn't yet cover that path), it blocks until every `data-controller` element on the page has its controllers connected. It is best-effort — it proceeds after a short timeout so a preview with no controllers can't hang the suite — and other system specs are pass-through.

### CSP violation capture

The Content-Security-Policy is enforced in test exactly as in dev and prod, and `spec/support/csp_violation_capture.rb` makes the browser tattle on violations. The source-level scan (`spec/code_smells/no_inline_event_handlers_spec.rb`) catches inline handlers, but the suite once shipped two CSP bugs it was structurally blind to: a blank-nonce generator that emitted an invalid `'nonce-'` and silently blocked every inline script for first-time visitors (#499), and an initializer override that un-enforced CSP in test (#500 follow-up). CDP-driven specs dispatch events at protocol level, so they never needed the blocked scripts — but the browser knows, and fires `securitypolicyviolation` for every block.

The support file installs one init script per browser process (the browser is reused across examples) that accumulates violations in `sessionStorage`, so same-tab navigations within an example don't lose them. An after-hook reads *and clears* the list — nothing bleeds across examples — and fails any example that produced a violation. The `ALLOWED_VIOLATIONS` list is empty by design; every future entry needs a written reason.

### WebAuthn virtual authenticator

`spec/support/webauthn_virtual_authenticator.rb` provides `with_virtual_authenticator { ... }`, which enables CDP's virtual authenticator (ctap2/internal, resident-key, `automaticPresenceSimulation: true`) so a system spec can drive real `navigator.credentials.create`/`get` calls with every gesture auto-approved.

The subtle part is **origin alignment**: the WebAuthn RP origin from the initializer is `http://localhost`, but Capybara binds its test server to `127.0.0.1:<dynamic port>` — and WebAuthn treats `127.0.0.1` and `localhost` as *different* origins. The helper temporarily sets `Capybara.app_host` to `http://localhost:<port>` so the browser's origin matches, and extends `WebAuthn.configuration.allowed_origins` to that exact URL (the port matters for the gem's origin check). Both are restored after the block.

## Troubleshooting the suite

### "Another process is holding the test database"

Each test database is one SQLite file, and `config/database.yml` installs a 5-second busy handler (#304). Two runners on the same test database therefore do not fail fast — every contended statement waits out the handler before raising, so the suite crawls and sheds failures across unrelated files, none of which name the cause. (Observed once in a fork: a 12-minute suite took 85 minutes and produced 30+ phantom failures.) `spec/support/test_database_lock_guard.rb` refuses to start a run into an already-locked database: a `before(:suite)` `lsof` check names the holding PIDs and the fix.

Two things to know when it fires:

- Stop the other run by **process group**, not by name — the guard's message prints the exact `kill -- -<pgid>` command. `pkill -f "bundle exec rspec"` is the trap: it matches the shell wrapper and orphans the child, which keeps the WAL lock, after which every run fails on the first `create(...)`.
- Parallel workers each get their own database file, but `TEST_ENV_NUMBER` is empty for worker 1 — so a parallel run and a plain `bundle exec rspec` genuinely do collide on `storage/test.sqlite3`.

The guard lives in the spec boot path rather than a wrapper script on purpose: a guard you have to remember to invoke protects nobody, and this way it covers the plain runner, every parallel worker, agent invocations, and IDE runners alike.

### "Compiled Tailwind stylesheet missing"

System specs load the compiled Tailwind stylesheet from the test server. When it is missing, axe reports contrast violations on every page and interaction specs fail on collapsed layout — 132 failures that name neither Tailwind nor assets. `spec/support/compiled_assets_guard.rb` checks for `app/assets/builds/tailwind.css` before each system spec and fails with the actual fix: `bin/rails tailwindcss:build`.

The hole is easy to fall into: `assets:clobber` (which `bin/setup` runs deliberately) also deletes the compiled stylesheet, and the tailwindcss-rails safety net that rebuilds it hooks `test:prepare` — the Minitest path, which `bundle exec rspec` never invokes. The guard is read-only by design: building the CSS from inside the suite would race, since `bin/parallel-rspec` boots one RSpec process per core.

## Next steps

- **[Accessibility](/docs/developer/accessibility)** — how the axe-core AAA checks fit into system specs.
- **[Architecture](/docs/developer/architecture)** — the tenancy and authorization invariants many of the guard specs enforce.
- **[Getting started](/docs/developer/getting-started)** — environment setup, including the pieces (`bin/setup`, compiled assets) the guards above assume.
