# Changelog

All notable changes to ModelRails are documented here, organized by phase.

## [Unreleased]

### Added

- Parallel test suite — `bin/parallel-rspec` runs RSpec across all cores with example-count and merged-coverage integrity gates; CI and the Lefthook pre-push gate use it, cutting CI's test job from ~14 to ~8.5 minutes (#485; further wins tracked in #486–#488).
- Runtime-balanced parallel test split — spec files split across workers by recorded per-file runtime instead of file size, evening out the slowest worker; the timing log (`tmp/parallel_runtime_rspec.log`) is written each run and cached in CI, and falls back to file-size splitting when absent (#488).
- Add opt-in encrypted form-draft recovery on invitation and project forms.
- Cancel superseded CI runs on new pushes to the same branch/PR (#489).

### Changed

- Replaced Playwright/Node with Cuprite (pure-Ruby CDP) for system specs, and swapped npm-based linters for Ruby gems (`erb_lint`, `mdl`) — the template no longer requires Node at all (#497).
- Bumped Ruby to 4.0.6 (#501).

### Fixed

- Devcontainer installs Chromium for Cuprite system specs — #502 removed the old `npx playwright install` browser step without a replacement, leaving the `ruby:slim`-based devcontainer with no browser to drive, so every system spec failed there; ferrum now auto-detects the apt-installed `chromium`. A template-invariant spec guards that a browser is installed and that Node stays out of `.devcontainer/`.
- Align `@playwright/test` to 1.61.1 (chromium-1228) to match the `playwright-ruby-client` gem's compatible version — fixes an `add_init_script` protocol skew that flaked the form-draft system specs.
- Toast containers are named region landmarks — clears the app-wide aria-prohibited-attr axe violation and keeps toast content inside a landmark.
- **Security:** CSP nonce generator returned blank on a visitor's first request (no session yet), emitting an invalid `'nonce-'` source that blocked every inline script — Stimulus never booted for first-time visitors (#499).
- Cookie-consent banner (biscuit-rails): reject is now the emphasized default action (not accept), the banner no longer flashes visible before JS hides it, and reopening the preferences panel shows the visitor's actual saved choices instead of stale checkboxes (#500).

## v2.0.0 — Passwordless Auth, Workspace Lifecycle & Navigation IA (2026-07-06)

### Breaking

- Git history rewritten to purge the internal root `docs/` directory (now the separate [modelrails_base_docs](https://github.com/dschmura/modelrails_base_docs) repo) — every commit SHA changed; existing clones and forks must re-sync (`git fetch && git reset --hard origin/main`).
- `config/deploy.yml` `servers.web` moved from a flat host list to a `hosts:` + `options:` structure for `max-replicas: 1`; forks that customized it must migrate — see `app/docs/deployment.md` (#135).
- Email verification switched to signed, stateless tokens; dropped the `verification_token`/`verification_sent_at` columns — links issued before upgrade stop working (#178).

### Added

- Workspaces index client-side filter + denser cards — the filter appears once the "Other workspaces" list is long enough to scan; each card sets the logo beside the name with a single metadata line (#428).
- Persistent workspace-identity bar anchoring the workspace shell, with tightened content spacing (#423).
- Workspace & project lifecycle — Archive (reversible; restore from the Archived section) and permanent Delete (workspace deletion gated by a type-the-name confirmation), cascading workspace → projects (#413, #414).
- Operator workspace lock — `rails "workspaces:suspend[slug]"` / `"workspaces:unsuspend[slug]"` puts a workspace on hold ("This workspace is locked."), blocking owners until released (#415).
- Passwordless-first sign-in — magic link is the default; a password is an opt-in set from Security settings (#374).
- Passkeys / WebAuthn — register platform authenticators and sign in with a discoverable credential (#375, #376).
- Browser-hosted GitHub Codespace — one-click cloud dev environment; boots, signs in, and runs the suite in-container (#385).
- Customizable Select picker — native `<select>` styled via `appearance: base-select` where supported, with an untouched native fallback elsewhere (#399, #402).
- `/docs` split into user and developer audience modes with an always-visible audience switcher (#381, #382).
- Per-project tools — extensible registry, per-project toggle, project-home tabs, and a self-hiding onboarding step (#364).
- First-run onboarding journey (`:none`) — name workspace → first project → invite, with a soft email-verification gate (#362, #363).
- `ClientAccess` model — scopes an external client to one project without a workspace membership or seat (#365).
- Per-project Clientside toggle, per-resource "share with client side" flag, and a read-only `Clientside::` area (#366).
- Client invite flow — `Invitation` client variant, `InvitationMailer#invite_client`, and client-only home routing (#367).
- `:none` onboarding posture (`WORKSPACE_ON_SIGNUP=none`) — signup creates no workspace; forks override `authenticated_home_path` (#343).
- Fork-owned brand-color seam `_brand.css` (`merge=ours`) — swap the primary palette without merge conflicts (#313).
- Deployment docs — Thruster X-Sendfile offload with a "don't set `x_sendfile_header`" guard, plus a health-check-timeout entry.
- `bin/deploy-guide` — target-aware deployment guidance (kamal / self-host / managed) plus a "without Kamal" contract section.
- Lookbook component explorer at `/lookbook` (development-only) for the vendored `UI::*` components.
- Vendored `UI::*` ViewComponents via the dev-only `modelrails_ui` gem; the form builder, `_modal`, and `avatar_for` delegate with no output change.
- Appearance destination time-zone picker — explicit `override=true` preserves the choice against the browser beacon (#154).
- Settings hub destinations — disambiguated H1s/descriptions, a shared page-header partial, and an Appearance page (#150).
- Settings hub mobile drawer — off-canvas sidebar below 768px with focus trap + ESC/click-outside dismiss (#148).
- Settings hub shell — sidebar-equipped `settings.html.erb` with context-adaptive, Pundit-gated items and Turbo morph.
- Personal-workspace OKLCH context ramp — desaturated slate via `[data-workspace-kind="personal"]`.
- Chroma-boosted workspace color swatch in the sidebar switcher.
- Notifications v1 — in-app bell + triage page, real-time broadcasts, preferences UI, email digests, and 10 notifier types (#48, #53–#56, #64–#71).
- Optional VS Code Dev Container matching the production image (#129).
- `.env.example` documenting required environment variables (#129).
- YJIT enabled in production (#129).
- CI builds the production Docker image on every PR (#134).
- Deployment, background-jobs, and dev-environment docs at `/docs` (#136).
- Clear "invitation was for a different email" notice on verification, signup, and accept (#177, #180).
- Single-tenant preset (`WORKSPACE_ON_SIGNUP=shared`) — one shared workspace, tenancy UI suppressed, env-driven seed.
- Per-workspace `join_policy` (`invite`/`open_link`) with a revocable `WorkspaceJoinLink`; both join flows wired; instance ceiling via `SIGNUP_PERMITTED_JOIN_STRATEGIES`.
- Fork seams — brand strings, `draw(:app)` product routes, extendable `/docs` categories, and `merge=ours` fork-owned paths.
- In-app forking guide at `/docs/forking`.

### Changed

- Workspace navigation IA — settings becomes a section of the workspace shell (Profile / Members / Limits under an active "Settings"), not a separate layout; drops the `settings_context` macro (#425).
- Mobile menu restructured — account actions first, workspaces below (recency-ordered, capped, with an "All workspaces" overflow) (#426).
- Mobile section-nav strip — in-page secondary nav replacing the header-accordion sub-nav hoist (#422).
- Email-first sign-in — one email field routes to password, magic link, or passkey; the connected-accounts page reflects real linked state (#377).
- Retired the deferred "personal workspace"/"personal profile" copy → "your workspace"/"your profile"; section label "Account" → "You" (honest-naming).
- Removed the half-wired dynamic-PWA scaffold; the static `public/manifest.webmanifest` stays (#306).
- Fork-readiness code-quality cleanup — duck-typed project resolution, narrower rescues, named activity-log records (#305).
- `.env.example` documents every operator-settable ENV var, with a template invariant guarding against drift (#298).
- SQLite `journal_mode: wal` declared explicitly in `config/database.yml`, with the busy-handler behavior pinned by spec (#304).
- CI lint tooling version-pinned — markdownlint + herb-lint in `package.json` via `npx`; dropped brakeman `--ensure-latest` (#299).
- Unified the UI signal vocabulary to `info·success·warning·danger`; signal chips move to tinted surfaces, fixing the muddy warning badge.
- Avatar notification indicator restored as a severity dot (v2) — desktop on the avatar, mobile on the hamburger; standalone bell removed.
- Email/password signup defers invitation acceptance until the email is verified (#175).
- `TENANCY_ONBOARDING` renamed to `WORKSPACE_ON_SIGNUP` — reads honestly (the app is always multi-tenant).
- Sidebar skips the personal-only `memberships` eager-load unless onboarding is `:personal` (#344).
- Workspaces index rewritten from phonebook to workbench — pinned-current row, last-accessed sort, inline Switch/Leave; adds `memberships.last_accessed_at`.
- Mobile shell — the header expands accordion-style inline, replacing the off-canvas drawer (#148).
- Header workspace switcher hides personal workspaces; the Settings sidebar switcher is the explicit switch surface (#145).
- Account, Notification, Security, and Workspace settings destinations use the shared settings page header.
- Motion-safe sidebar transitions; `data-settings-context-kind` → `data-workspace-kind`; hover prefetch on settings/switcher links.
- Route consolidation — `workspaces#edit` serves Profile, `workspaces/settings#edit` narrows to Limits & Plan (Admin-visible via `ProfilePolicy`).
- Notifications bell is a standalone header affordance; the user menu collapses to an identity block + sign-out.
- Mobile-accordion sidebar contents flow inline via chrome-free `_*_sidebar_items` partials.
- Sidebar items gain a divider and a context-aware section label (`Account`/`Workspace`).
- Sidebar nav items gain Heroicons v1 outline icons (8 new SVGs, auto-discovered).

### Removed

- `/me` ("Your home") — the workspace home consolidates to `/workspaces`, which gains an identity anchor (#429).
- Deprecated `invitations#index` redirect route + the redundant "Invitations" sidebar item — folded into the members surface (#398).
- `settings-drawer` Stimulus controller, `*.mobile_drawer.*` locales, and the off-canvas markup — superseded by the header accordion.
- `Workspaces::BrandingsController` + `/workspaces/:slug/branding/*` routes — identity picker moved to `WorkspacesController#identity_picker_hub`.
- `Workspaces::BrandingPolicy` — replaced by `Workspaces::ProfilePolicy`.
- Orphan header dropdown partials + the `navigation.new_workspace` locale — completes Path Y (the sidebar switcher is canonical).
- Header "Workspaces" text link + the `navigation.workspaces` locale — the sidebar switcher is the sole workspace affordance.

### Fixed

- Dev mail-preview location — `/letter_opener` (a Rails engine on the app), not the dead port 1080; corrected across the devcontainer, setup message, `/docs`, and the invariant spec (#431).
- `base-select` chevron layout + de-duplicated select labels (#421).
- Signups-closed sign-in view renders inside the turbo-frame instead of vanishing (#384).
- Codespaces boot — trixie `moby:false`, `bin/setup` (libssl-dev + Node), non-interactive Playwright, Solid Queue self-heal, and forwarded-proxy CSRF Origin (#386, #387, #388, #396, #397).
- Settings-hub Turbo morph is now actually active — `_layout_head` yields `:head` so the morph meta emits (#327).
- Single-tenant preset — invitation-driven signups adopt the invitation's role instead of a placeholder Member.
- Unauthenticated invitees can accept under invite-only signup — the accept page stashes the pending token (#345).
- Development mailer URLs follow the running `PORT` so letter_opener links work on non-default ports (#346).
- `Broadcastable` respects subclass `broadcast_events` overrides (destroys broadcast on `ProjectMembership`).
- Fixed the production `docker build` failure after the Ruby pin change (#132).

### Accessibility

- Alert severity icons (modelrails_ui v0.5.0) — a colour-blind-safe non-colour cue on info/success/warning/danger alerts; normalized warning triangle (#427).
- Quiet-hours warning sits in a stable `role="status"` wrapper so screen readers reliably announce it (#302).
- `autocomplete="off"` on the read-only join-link copy field, clearing the herb-lint warning (#299).
- WCAG 2.2 AAA contrast pass — six tokens bumped to 7:1; `text-muted` matches `text-body` (hierarchy via size/weight).
- axe-core CI promoted `wcag2aa` → `wcag2aaa`, with contrast-ratio/hex/font diagnostics in failures.
- Code blocks at `/docs` meet WCAG 2.2 AAA contrast in both themes (#137).

### Security

- New-member admission blocked into archived, deleted, or locked workspaces on every path — join links, invitations, signup claims, and the client area — with generic copy that never reveals which lifecycle state blocked an outsider (#417).
- Home workspaces (personal, and the shared instance workspace) can no longer be archived or deleted — a policy exemption plus a model guard that also covers console and direct-call paths (#417).
- Dependency CVE bumps — nokogiri/faraday (#371), css_parser 3.0.0/msgpack 1.8.3 (#400); unfixable thruster Go CVEs ignored in the image scan (#380, #395).
- Invitation acceptance bound to the invited email across every path and deferred until verified — a leaked link can't be redeemed by someone else (#175, #176).
- Per-recipient email throttle across senders — prevents N attackers from collectively flooding one inbox.
- Cross-user OAuth collision alert — a defense-in-depth email when someone tries to link your identity to another account.

### Maintenance

- `bundler-audit` runs in Lefthook pre-push, mirroring CI `scan_ruby` (#372).
- Bullet safelists consolidated into one shared source (`lib/bullet_safelists.rb`) so development and test can't drift (#403).
- `modelrails_ui` bumped to v0.4.0 (customizable-select); component previews de-flaked by dropping external CDN assets (#401, #373).
- Ruby bumped to 4.0.4 and enforced by Bundler across dev, CI, and production (#129).
- Production image no longer ships test gems (#129).
- Production deploys constrained to one web container with a longer job-drain window (#135, #130).
- Solid Queue uses named queues (`default`/`mailers`/`low`) (#135).
- Faster CI on native architectures via parallel bootsnap precompile (#131).
- IDN punycode normalization in `EmailNormalizer` for canonical email comparison.

## v1.4.0 — OAuth Hardening & Design System Primitives v2 (2026-04-28)

### Security

- Email normalization for storage and equality comparison now uses Unicode NFC + downcase + strip via a new `EmailNormalizer` module (`app/lib/email_normalizer.rb`). The `User` model's `normalizes :email_address` and `:pending_email` declarations route through it, so all `find_by` lookups and writes get canonical form (Rails 7.1 auto-applies normalizers to lookup values). The OAuth callback's "OAuth email matches user's primary email" check uses `EmailNormalizer.equivalent?` so an email like `café@example.com` matches itself across NFC vs NFD encodings — previously these would compare as different bytes despite being visually identical, forcing international users through email verification on every OAuth sign-in. Gravatar SHA-256 hashing also uses canonical form so the same email always produces the same Gravatar URL regardless of input encoding. IDN punycode conversion (e.g., `bücher.de` ↔ `xn--bcher-kva.de`) is NOT handled — explicitly deferred until a real interop concern surfaces; would require an addressable-style gem.
- `Authentication#generate_verification_token!` now retries up to 3 times on `ActiveRecord::RecordNotUnique` (defensive against the astronomically-unlikely 256-bit token collision). The `Account::ConnectedAccountsController#resend_verification` action also rescues `RecordNotUnique` at the request level — if every regenerated token still collides, users see a graceful "try again" alert instead of a 500 error.
- OAuth callbacks now check `auth_hash.info.email_verified` before auto-verifying or auto-linking. When an OAuth provider explicitly reports the email as unverified (Google's `info.email_verified: false` for unverified Google accounts), `OmniauthCallbacksController` no longer (a) auto-verifies a newly-linked authentication for a signed-in user even when the OAuth email matches the user's primary email, (b) auto-links a brand-new OAuth signup to an existing verified user account by email match, or (c) auto-verifies and signs in a fresh user from OAuth — instead, the new user is created with a pending authentication and a verification email is sent without signing them in. Closes the account-takeover surface where an attacker could create an unverified Google account using a victim's email and have the app auto-link the OAuth identity to the victim. Providers that don't expose `info.email_verified` (e.g., GitHub) are treated as implicitly verified — only an explicit `false` triggers the gate, preserving existing GitHub OAuth behavior.

### Added

- Design system primitives v2: semantic spacing tokens (`--space-section-gap`, `--space-row-padding`, `--space-action-group-gap`, `--form-input-height`) defined in `app/assets/tailwind/tokens/_spacing.css`. Tokens are CSS-var-only — never registered in `@theme` so they don't leak as Tailwind utility classes. Consumed inside `@layer components` rules and `TailwindFormBuilder` constants.
- Component utilities under a new `@layer components` block in `app/assets/tailwind/application.css`: `.btn-touch-target` (44×44 minimum, reads `--form-input-height`), `.btn-text` (font-weight/underline/focus-visible base), `.btn-text-danger` and `.btn-text-interactive` (color variants), `.action-group` (inline-flex with `--space-action-group-gap`).
- Layout utility `.page-container` (`max-w-2xl mx-auto px-4`) for narrow page wrappers — settings, account, and form-centric flows.
- `design-system.md` (now in [modelrails_base_docs](https://github.com/dschmura/modelrails_base_docs)) — single-source reference for the spacing convention, semantic tokens, component utilities, class ordering convention, and migration recipe. Linked from README.md.

### Changed

- `app/views/sessions/email_error.html.erb` now uses `TailwindFormBuilder` via a new `EmailLookupForm` ActiveModel form object (`app/models/email_lookup_form.rb`). The view no longer hand-rolls form-input classes; the form builder auto-applies error styling, ARIA attributes (`aria-invalid`, `aria-describedby`, `role="alert"`), and inline error messages from the model's `errors` API. Validation is unified: blank email, missing email, and malformed email all surface the same `sessions.lookup.invalid_email` notice ("Please enter a valid email address."). Closes the v1.3.0 design-system debt note about this view bypassing the form builder.
- Refactored `app/views/account/connected_accounts/index.html.erb` to consume the new utilities (proof refactor — same visual output as before). Subtle visual change: the Resend button now inherits `font-medium` from `.btn-text`, matching Cancel and Disconnect. This unifies a pre-existing inconsistency where Resend was visually slightly lighter than the other text buttons.
- `TailwindFormBuilder` (`app/form_builders/tailwind_form_builder.rb`) now reads `--form-input-height` via `min-h-[var(--form-input-height)]` in three constants (`FIELD_BASE`, `SUBMIT_CLASSES`, `FILE_FIELD_CLASSES`) instead of hardcoded `min-h-[44px]`. Single source of truth for touch-target height across all form inputs, submit buttons, and file fields. Same 44px value, named source.
- `.btn-text` uses `focus-visible:` (not `focus:`) for the focus ring, matching the project's existing `.biscuit-btn` pattern. Focus rings now appear for keyboard navigation but not for mouse clicks.

### Fixed

- ERB lint job (`herb-lint`) now passes on `_a11y_sim.html.erb` after refactoring the dev-only mode-icons hash from `<% end,` syntax (rejected by herb-lint 0.9+'s `parser-no-errors` rule) to separate `capture do %>...<% end %>` assignments. Same compiled output, parser-friendly structure.
- CI test job now installs `libvips42t64` on the Ubuntu runner so Active Storage image variants generate without `LoadError`. Affected 9 identity-picker system specs that all failed with the same shared-library load error; root cause was missing system dependency, not test logic.
- Replaced the flaky `expect(page).not_to have_css("script")` assertion in the registration XSS-prevention spec with a deterministic raw-HTML byte check (`page.html.include?("<script>alert('xss')</script>")` plus a positive control on the escaped form). The original assertion depended on Capybara's visibility filter excluding hidden layout `<script>` tags, which Playwright sometimes computed inconsistently during page transitions.

---

## v1.3.0 — Verified OAuth Account Linking

### User-facing

- **Email verification for OAuth links with mismatched email.** When a signed-in user links a new OAuth provider whose email differs from their primary email, the linked authentication is created in pending state and a confirmation email is sent to the OAuth-returned address. The user must click the verification link before that sign-in method is active. Auto-verifies when the OAuth email matches the primary email (case-insensitive, whitespace-trimmed)
- **Pending state UI** on the connected accounts page: pending rows render in info-styled treatment with the email being confirmed, a help line ("Check your email…"), and dedicated **Resend confirmation** + **Cancel link** buttons. Verified rows keep the **Unlink** button (renamed from "Disconnect" for verb-pair consistency with "linked")
- **Post-OAuth confirming banner** appears once after the OAuth callback redirects back to connected accounts, calling out the email being confirmed and which provider is being linked
- **Provider display names** now render as "GitHub" (not the `titleize`-mangled "Github"), backed by an `Authentication.display_name_for` lookup used by every flash message, mailer subject, and view that names a provider
- **Token-based verify URL** at `GET /account/connected_accounts/verify/:token` works for both signed-in and signed-out users — clicking from an email client redirects appropriately afterwards
- **Resend confirmation** action on each pending row regenerates the token and emails it again. Rate-limited per user

### Security

- **Closes the OAuth-linking email-ownership gap.** Previously, `OmniauthCallbacksController#create` set `verified_at: Time.current` on every signed-in linking attempt, regardless of whether the OAuth-returned email belonged to the user. The new flow refuses to activate the sign-in method until the user proves mailbox ownership of the OAuth email. Pending authentications cannot sign in
- **Cross-user collision blocked.** A signed-in user re-OAuthing with credentials matching another user's existing authentication never transfers ownership; flash leaks no information about whether the token belongs to a different account
- **Cross-user verification spam prevented.** A signed-in attacker can no longer trigger fresh verification emails to a victim by re-OAuthing on the victim's pending UID — the cross-user check fires before the pending-resend branch
- **Per-user rate limit scoping** on `resend_verification`, `account/avatars#update`, and `workspaces/invitations#resend` (`by: -> { Current.user&.id || request.remote_ip }`). Prevents shared-NAT lockout where one user could exhaust another's rate bucket
- **Cross-user verify guard** on `Account::ConnectedAccountsController#verify` — a signed-in user clicking another user's verification link gets the same `invalid_or_expired` flash as a stale token, with no programmatic confirmation that the token belonged to a different account
- **Last-verified-method protection** now counts only verified authentications. Pending auths can always be cancelled (they grant no sign-in capability); a verified auth can only be removed if at least one other verified auth remains
- **Transactional destroy with row lock** (`SELECT ... FOR UPDATE` on Postgres/MySQL; `BEGIN IMMEDIATE` on SQLite) serializes concurrent DELETE requests, preventing the race where two simultaneous unlinks could both pass the count gate
- **Atomic pending-row creation** — the verification token is set in the same SQL write as the auth row's initial `save!`, eliminating the transient state (`verified_at: nil` AND `verification_token: nil`) where a crash mid-flow could leave a row that bypassed verification on a subsequent OAuth attempt
- **Production fix:** `omniauth-google-oauth2` returns `provider: "google_oauth2"` from real callbacks, but the `Authentication` enum stores `"google"`. The new `PROVIDER_MAP` normalizes the strategy name to the enum value at the controller boundary. Without this normalization, every real Google OAuth callback would have raised `ArgumentError: 'google_oauth2' is not a valid provider`. The bug existed pre-feature; this branch fixes it and adds a regression spec that exercises the strategy default

### Accessibility (WCAG 2.2 Level AAA target)

- **`role="status" aria-live="polite" aria-atomic="true"`** on the post-OAuth confirming banner so screen readers announce the verification-pending state
- **`<ul role="list">` + `<li>`** semantic markup for the authentication rows (was `<div>`/`<div>`)
- **`aria-label`** on each `<li>` describing pending-vs-verified state (e.g., "Google sign-in method, pending verification") so the row's status is programmatically determinable
- **Mailer body contrast fixed:** `.what` text bumped from `#6b7280` (4.8:1) to `#374151` (~10.6:1, AAA); `.footer` text bumped from `#9ca3af` (2.8:1, fails AA) to `#4b5563` (~7.6:1, AAA)
- All Resend / Cancel link / Unlink buttons retain `min-h-[44px] min-w-[44px]` touch targets and `focus:ring-2` focus indicators
- HTML mailer template links to a single descriptive CTA ("Yes, this was me — finish linking"), not "click here"
- Plain-text alternative provided for the verification email

### Infrastructure

- **1116 examples, 0 failures**; line coverage ~94%, branch coverage ~82%
- **35 commits** across two merged branches (`feat/verified-oauth-linking` and `chore/oauth-linking-followups`), each commit independently bisect-safe
- New schema column: `authentications.email` (nullable string, captures OAuth-returned email per row)
- New routes: `POST /account/connected_accounts/:id/resend_verification`, `GET /account/connected_accounts/verify/:token`
- New mailer: `AuthenticationMailer#link_verification_email` + HTML/text templates
- New model methods: `Authentication#display_provider`, `Authentication.display_name_for`, `Authentication#assign_verification_token` (non-persisting helper used by both the controller's atomic-create path and the model's `generate_verification_token!`), `Authentication#pending?`, `Authentication#token_expired?`, scope `Authentication.pending`. The legacy `Authentication#verification_token_expired?` now delegates to `token_expired?` so `TOKEN_LIFETIME` is the single source of truth for the 24h window
- New controller actions: `Account::ConnectedAccountsController#verify`, `#resend_verification`. `#destroy` rewritten to count only verified auths, with transactional row-lock semantics. `OmniauthCallbacksController#create` decomposed into `handle_existing_auth` / `handle_signed_in_link` / `handle_new_user_oauth` private branches with a `PROVIDER_MAP` normalization helper
- New locale files / blocks: `config/locales/en/oauth.en.yml` (new file with `omniauth_callbacks.create.*` keys), expanded `account.en.yml` blocks for `connected_accounts.index/destroy/verify/resend_verification`, `authentication_mailer.link_verification_email.*` keys
- Design doc and implementation plan preserved in [modelrails_base_docs](https://github.com/dschmura/modelrails_base_docs) at `superpowers/specs/2026-04-25-verified-oauth-account-linking-design.md` and `superpowers/plans/2026-04-25-verified-oauth-account-linking.md`

### Acknowledged limitations (deferred)

- **`info.email_verified: false` from Google is not gated.** If a Google IdP reports the OAuth email as unverified at the provider level, the new-user OAuth signup path still trusts it. Closing this requires a product decision (refuse OAuth signup, or require an additional verification step) and is tracked separately
- **Email comparison is byte-exact ASCII.** International/IDN addresses (e.g. `Юлия@example.ru`), Turkish dotless-i, and `+`-aliased addresses are treated as different from their canonical form, routing through verification even when visually identical to the user's primary. Acceptable for an English-first starter kit; tracked for later if/when IDN parity matters
- **Resend collision under simultaneous double-click** raises `RecordNotUnique` (DB unique index on `verification_token` saves correctness) but isn't gracefully rescued in the controller. Effectively rate-limited to 3-per-3min, so unlikely to manifest in practice

---

## v1.2.0 — Footer Cohesion + Developer Ergonomics

### Footer (user-facing)

- Two-row layout: brand + clustered navigation on row 1, centered copyright on row 2
- Nav links grouped into **Product** (About, Docs) and **Legal & privacy** (Privacy, Contact, Cookie settings) clusters separated by a vertical divider
- "Cookie settings" replaces the Biscuit gem's floating bottom-left button; the Biscuit preferences panel now reopens from an in-footer link via a 10-line `footer_controller.js` Stimulus controller that dispatches to the gem's hidden action button
- Responsive: mobile stacks vertically, tablet wraps and centers, desktop anchors left with the dev trigger pushed right
- WCAG 2.2 Level AAA target size: all footer links and the Cookie settings button use `min-h-[44px]`

### Developer tools (development-only, never rendered in production)

- **Clickable letter_opener link on "Check your email"** — the H2 on `sessions/check_email.html.erb` becomes a link to `/letter_opener` in development, opening the sent email in a new tab without leaving the auth flow
- **Accessibility-simulation drop-up in the footer** — toggle between Normal, Blur, Grayscale, Deuteranopia, Low contrast, and Cataract filters to pressure-test pages against vision-impairment conditions. Keyboard: Cmd/Ctrl+Shift+A opens, 0–5 jump to modes, Esc / Tab closes. State persists across reloads via localStorage; live region announces mode changes for screen readers
- **`aria-live` status region** on the a11y sim for WCAG 4.1.3 compliance
- **`aria-hidden` SVG filter defs** inlined in the partial; body-level CSS filter classes applied to `<body>` so modals and toasts receive the filter

### Fixes

- Disable CSP on `LetterOpenerWeb::ApplicationController` in development. The production CSP's `frame_src: :none` and nonce-enforced `script_src` blocked the gem's email-preview iframe and inline scripts. The engine is dev-only (mounted conditionally in `config/routes.rb`), so the override is scoped safely via `Rails.application.config.to_prepare`

### Infrastructure

- 1025 examples, 0 failures; coverage 94.46% line / 82.05% branch
- New view spec (`spec/views/shared/footer_spec.rb`) and system spec (`spec/system/footer_cookies_spec.rb`) covering footer structure, link clusters, and Cookie settings reopen flow
- Design doc and implementation plan preserved in [modelrails_base_docs](https://github.com/dschmura/modelrails_base_docs) at `superpowers/specs/2026-04-22-footer-cohesion-design.md` and `superpowers/plans/2026-04-22-footer-cohesion.md`

---

## v1.1.0 — Auth Redesign: Smart Sign-In + Magic Links

### Smart Sign-In Flow
- Unified email-first sign-in: single email field intelligently routes users
- Existing user with password → password form (within Turbo Frame)
- Existing passwordless user → magic link sent, inline "check your email" confirmation
- Unknown email → registration magic link sent, same inline confirmation
- "Send me a sign-in link instead" option on password form for password users

### Magic Links
- MagicLinkToken model with secure token generation, 15-minute expiry, one-time consumption
- Magic link sign-in for existing users (clears token after use)
- Passwordless registration via magic link (name-only form, no password required)
- Registration auto-creates verified email authentication record
- MagicLinkMailer with sign-in and registration email templates

### UI
- Turbo Frame inline transitions: check-email confirmation replaces sign-in form in-place
- Screen reader announcements via `role="status"` and `aria-live="polite"`
- `aria-hidden="true"` on decorative icons

### Security
- Rate limiting on magic link requests (5 per 3 minutes)
- Rate limiting on session lookup (10 per 3 minutes)
- No information leakage: same response for existing and non-existent emails
- Token consumed on first use, preventing replay

### Infrastructure
- 550 examples, 0 failures, 95.7% line coverage
- System specs for full magic link sign-in and registration flows
- Request specs for all magic link endpoints

---

## v1.0.0 — Phase 5B: Admin + Security + Polish

### Admin
- Rake tasks: `users:unlock[email]`, `users:verify[email]`, `users:suspend[email]`
- Suspend destroys all sessions and deactivates all memberships

### Real-Time
- Turbo Stream broadcasts on workspace and project streams
- Morph-based refresh (`broadcast_refresh_to`) — no partial rendering in models
- Workspace stream: membership, invitation, project, and settings changes
- Project stream: resource and project membership changes
- Resilient: broadcast failures never break primary operations

### Security
- Security headers initializer (X-Frame-Options, Referrer-Policy, Permissions-Policy, CSP)
- Rate limiting on registration and password reset endpoints (Rails 8 `rate_limit` DSL)
- All auth endpoints now rate-limited (login was already covered)

### Documentation
- Markdowndocs gem integration at `/docs`
- Starter docs: Getting Started, Architecture, Extending, Security
- Security docs include Top Secret and Rack::Attack production recommendations

### Infrastructure
- 439+ examples, 0 failures
- Brakeman clean (1 known mass assignment note)
- 95%+ line coverage

---

## v0.5.0-alpha — Phase 5A: Resource Layer + Activity Tracking

### Resources
- Polymorphic Resource registry with title, status (draft/published), position, and type allowlist
- Document content type with Action Text (Trix) rich text editor
- One controller serves all resource types — type-specific form/display partials
- ResourcePolicy enforces project membership access (viewer reads, editor creates, creator manages)
- Drag-and-drop reposition via Turbo Stream

### Activity Tracking
- ActivityLog model with polymorphic trackable, workspace scoping, and visibility enum (workspace/admin)
- Trackable concern with `after_commit` callbacks — opt-in per model
- Automatic creation/update tracking on Workspace, Membership, Invitation, Project, and Resource
- Sensitive attribute filtering (tokens, passwords stripped from metadata)
- Failure resilience — tracking errors never break primary operations
- Activity feed on workspace and project show pages

### Infrastructure
- Action Text installed for rich text content
- 404 examples, 0 failures, 95.8% line coverage
- 1 Brakeman note (same known mass assignment on project membership)

---

## v0.4.0 — Phase 4: Projects + Collaboration Spaces

### Projects
- Lightweight, Basecamp-style collaboration spaces within workspaces
- Project CRUD with slug routing, description, and max_projects enforcement
- Enum roles on ProjectMembership (creator/editor/viewer)
- Creator auto-assigned on project creation
- Direct member add for workspace members with role selection
- Pin/unpin projects for quick access (IDOR-safe: finds by current user)
- Logo upload with initials fallback, OKLCH primary color picker
- Soft delete (Discardable) for project archiving

### Personal Workspace
- Auto-created on user sign-up (invisible in consumer UIs)
- Backfill rake task for existing users: `rails users:backfill_personal_workspaces`

### Project Invitations
- Polymorphic invitation reuse (invitable_type: "Project")
- Auto-adds invitee to workspace (as viewer) + project in one step
- project_role field on invitations (editor/viewer only — "creator" injection blocked by validation)
- Branching accept! flow for workspace vs project invitations
- Handles archived project rejection, discarded member reactivation

### Renames
- `max_teams` → `max_projects` (column + all references)
- `manage_teams` → `manage_projects` (permission JSON data migration)

### Infrastructure
- Workspace membership cascade: deactivating a workspace member destroys their project memberships (in transaction)
- Pundit policies for Project and ProjectMembership
- 280 examples, 0 failures, 94.2% line coverage
- 1 Brakeman note: `user_id` in project membership strong params — intentional, guarded by Pundit creator-only policy

---

## v0.3.0 — Phase 3: Invitations + Membership Lifecycle

### Invitations
- Email invitations with role assignment and 7-day expiry
- Batch invitations (multi-line email input, single role)
- Magic link invitations (shareable token URL, no email required)
- Resend (regenerates token, resets expiry) and revoke actions
- Polymorphic invitable (ready for Team invitations in Phase 4)
- InvitationMailer with accept/decline links

### Accept/Decline Flow
- Token-based accept page (works for authenticated and unauthenticated users)
- Unauthenticated users redirected to registration, auto-joined after sign-up
- Token-based decline with confirmation page
- Guards against expired, revoked, and already-used invitations

### Membership Lifecycle
- Role change by Owner/Admin
- Member deactivation (soft delete) with last-owner protection
- Member reactivation
- Ownership transfer (atomic: promote target, demote self)

### Authorization (Pundit)
- Pundit policies for Invitation, Membership, Workspace, Settings, Branding
- Permission checks via Role.permissions JSON (manage_workspace, manage_members, manage_teams, manage_settings)
- Retrofitted Phase 2 controllers (replaced inline role checks)
- Graceful rescue_from for unauthorized access

### Infrastructure
- 217 examples, 0 failures, 92.3% line coverage
- 0 Brakeman warnings

---

## v0.2.0 — Phase 2: Workspaces + Multi-tenancy + Ownership + Branding

### Workspaces
- Create, edit, and archive workspaces with auto-generated slugs
- Path-based routing (`/workspaces/:slug/...`)
- Plan enum (free, pro, enterprise) with no tier enforcement (forker's job)
- Configurable max members and max teams per workspace

### Multi-tenancy
- `Current.workspace` for request-scoped workspace context
- `Tenanted` concern with explicit `for_current_workspace` scope (no default_scope)
- `WorkspaceScoped` controller concern for nested controllers
- Session-tracked current workspace for navigation state

### Roles and Membership
- 4 seeded system roles: Owner, Admin, Member, Viewer
- Permissions JSON on roles (data model ready for Phase 3 Pundit policies)
- Workspace-scoped custom roles at data model level
- Creator auto-assigned as Owner on workspace creation
- Read-only members list
- Owner/Admin role check on settings and branding

### Branding
- Workspace logo upload (Active Storage) with initials fallback
- OKLCH primary color picker with live CSS variable preview (Stimulus)

### UI
- Workspace switcher dropdown in navigation (keyboard-navigable)
- App theme updated from cyan to sky throughout
- `Discardable` concern for consistent soft delete pattern

### Infrastructure
- Bullet gem for N+1 detection (raises in test, alerts in development)
- Brakeman verified clean (0 warnings)
- 133 examples, 0 failures, 89.7% line coverage

---

## v0.1.0 — Phase 1: Auth + Users + Static Pages

### Authentication
- Email/password sign-up with 12-character minimum and Pwned breach detection
- Sign in/out with Rails 8 DB-backed sessions
- Account locking after 5 failed login attempts, auto-unlock after 1 hour
- Password reset using Rails 8.1 built-in signed tokens
- Email verification with token-based flow and 24-hour expiry
- Resend email verification

### OAuth
- Google and GitHub sign-in via OmniAuth
- Automatic account linking by matching email
- Signed-in users can link additional OAuth providers
- OAuth-only users can add email/password sign-in

### Account Management
- Profile editing (first name, last name, email)
- Avatar upload via Active Storage with Gravatar fallback
- Connected accounts view with unlink protection for last sign-in method
- Theme preferences (light, dark, system) with Turbo Stream and Stimulus

### Static Pages
- Home, About, Privacy, Contact with I18n and WCAG 2.2 AAA accessibility

### Infrastructure
- Rails 8.1 with SQLite, Propshaft, Importmaps, TailwindCSS 4
- RSpec, FactoryBot, Capybara + Playwright test suite (77 examples)
- SimpleCov coverage reporting
- Devcontainer configuration for VS Code / Codespaces
