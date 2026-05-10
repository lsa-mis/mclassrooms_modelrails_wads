# Changelog

All notable changes to ModelRails are documented here, organized by phase.

## [Unreleased]

### Added

- **Notifications foundation (PR-1).** Installs the `noticed ~> 2.5` gem and ships the substrate for a per-user notifications system: `noticed_events` + `noticed_notifications` tables (gem-canonical), hardened with a partial unique index on a dedicated `idempotency_key` column for atomic concurrent-dispatch deduplication, FK cascade on `event_id`, and check constraints (`seen_before_read`; `recipient_type = 'User'` for v1 commitment). Adds `notification_preferences` (json, with full default JSONB matrix), `digest_next_due_at`, and `digest_last_sent_at` columns to `user_preferences` (existing rows backfilled across a randomized 24-hour window to avoid first-cycle thundering herd). New `NotificationPreferences` value object centralizes the load-bearing DND-vs-security rule (`do_not_disturb` suspends all delivery EXCEPT for the `security` category). New `ApplicationNotifier` base class with column-based idempotency, sentinel `:delivered`/`:deduplicated` return on `#deliver`, and `notification_methods do ... end` block providing `recipient_pref(channel)`, `recipient_locale`, `mark_seen!`, and `render_safe_or_placeholder`. Two smoke-test Notifiers (`WorkspaceInvitationReceivedNotifier`, `PasswordChangedNotifier`) prove the pattern end-to-end. No user-facing UI yet — that ships in PR-3. Web Push explicitly deferred to v1.1 as a clean additive change. Test count: 1201 → 1289 examples (88 new), 0 failures. See `docs/superpowers/specs/2026-04-30-notifications-design.md` for the full design rationale.

- **Notification preferences UI (PR-4 of 5).** New surface at `/account/notification_preferences` (linked from the user menu) lets users tune what notifications reach them and how. Four sections, each its own `<form>` with Turbo Stream auto-save (no Submit button — every toggle commits as it changes): a master "Pause non-essential notifications" DND toggle (Security alerts always go through, per `NotificationPreferences#allow?`'s security bypass); a 5×3 category × channel matrix (`security` / `account_access` / `workspace_activity` / `project_activity` / `billing` × `in_app` / `email` / `digest`) where Security's in-app + email cells render disabled with "Always on" help text and submit a hidden `true` so the JSONB carries the canonical state; digest cadence (Daily / Weekly) + time-of-day picker, displayed in the user's IANA timezone (stored on `UserPreferences.timezone`); and a retention dropdown (30 / 60 / 90 / 180 / 365 / Never) gated server-side by an allowlist (other values 422). Cadence or hour changes trigger an atomic recompute of `digest_next_due_at` so the indexed range scan PR-5's `DigestMailerJob` will rely on stays accurate. Bell-trigger gains a `title=""` tooltip ("X unread (Y hidden by Do Not Disturb)" via the existing `notifications.bell.unread_with_dnd` locale) when DND is on AND user has unread, surfacing the suppression to sighted hover/focus users without taking up nav-bar real estate. New tiny Stimulus controller `auto_submit` (~10 lines) wraps the auto-save pattern; new shared `_toggle.html.erb` partial used 16× on this one page (master + matrix). Plan-deviation notes: `Current.user.preferences` (not `user_preferences` per plan), `UserPreferences.timezone` (not `User.timezone` per plan), nav link added to user menu (plan called for `app/views/account/_navigation.html.erb` which doesn't exist — same recurring gotcha as PR-3 Task 12).

- **In-app notification surfaces (PR-3 of 5).** Bell icon + dropdown panel embedded in the user-menu chrome, dedicated `/account/notifications` triage page with filter chips (All / Unread / Security / Account & Access / Workspace / Project / Billing), per-row Mark-as-read/Mark-as-unread/Delete with Turbo Stream replace on update, and bulk Mark-all-read / Delete-all-read gated by the project's existing `shared/confirm_dialog` modal. Real-time arrival broadcast via `Turbo::StreamsChannel.broadcast_replace_to` against `[recipient, :notifications]` — fires from `ApplicationNotifier#after_create_commit` (the Event level, not the Notification, because Noticed v2's `Deliverable#deliver` uses `notifications.insert_all!` which bypasses ActiveRecord callbacks on the Notification class). The broadcast targets a small `_notifications_bell_button.html.erb` fragment that does only a single `where(read_at: nil).count` query, keeping the broadcast cheap and side-effect-free across the test suite. A second turbo-stream `update` to `#notifications-live` carries the localized "New notification" announcement so screen-reader users get an arrival signal without competing for focus (polite + atomic). Click-to-open via `GET /account/notifications/:id/open` marks read (idempotent) and redirects to the notifier's own `#url`, so each notifier subclass owns its destination. Cmd/Ctrl+Shift+N global keyboard shortcut toggles the dropdown from anywhere. Engine-route compatibility: the dropdown partial uses `main_app.` prefix on every route helper so the bell renders correctly inside the `/docs/*` markdowndocs engine layout. AAA contrast verified by axe-core in both themes on the dropdown + index pages, full keyboard navigation through Tab/Enter/Escape, 44×44 minimum touch targets via `.btn-touch-target`, no animation classes (trivially compliant with `prefers-reduced-motion: reduce`).

- **Notifications event catalog (PR-2 of 5).** Ten Notifiers now wired to domain events and scheduled triggers, completing the v1 catalog with in-app + per-channel preference gating + DND-vs-security routing + per-recipient email throttle + idempotency-key dedup. Specifically: `WorkspaceInvitationAccepted/Declined/ExpiringSoon`, `WorkspaceMemberAdded`, `WorkspaceRoleChanged`, `ProjectMembershipChanged` (all model-callback driven); `SignInFromNewDeviceNotifier` (security alert with browser-fingerprint heuristic via `User#last_known_browsers` JSON column + UA+OS SHA-256 digest, with the per-Notifier idempotency key folding the digest in so distinct devices in the same minute do not silently collapse); `WorkspaceCapacityApproachingNotifier` (billing alert at 80% of `max_members`, with day-bucket per-(workspace, metric) idempotency); two scheduled sweep jobs (`WorkspaceInvitationExpiringSweepJob` every 6h, `WorkspaceCapacitySweepJob` every 12h); and a `NotificationMailer` with five email methods, all using the established 5-key locale shape (heading/subject/greeting/body/action) for WCAG 2.2 AAA-aligned plain-text and HTML templates (purpose-driven `<h1>`, not greeting). The expiring-soon Notifier carries a day-bucket idempotency override so repeat sweep ticks do not produce per-tick alert volume; each in-window invitation produces at most one notification per day until accepted/declined. Locale-key placeholder vocabulary normalized across `notifications.<event>.message` and `notification_mailer.<event>.body` (`%{role}` → `%{new_role}` for the role-changed and member-added bodies). Adds `Workspace#owners` helper for the full owner roster. New `:billing` category and new `:workspace_capacity_approaching` `EmailRecipientThrottle` bucket. Projects-metric capacity sweep intentionally deferred to v1.x — PR-2 ships members-only, the column is in the schema, but the alert volume / tier-aware copy / UX direction is its own pass.

### Bug fixes

- **`Broadcastable` concern now respects subclass `broadcast_events` overrides.** The previous `included do; after_commit :broadcast_changes, on: broadcast_events; end` evaluated `broadcast_events` at include-time, freezing it to the concern's default `[:create, :update]` and silently ignoring any subclass override placed *after* `include Broadcastable`. As a result, `ProjectMembership`'s `:destroy` override had no effect — destroys were not broadcasting. The concern now registers three independent `after_*_commit` callbacks gated by `if:` lambdas that lazily resolve the override at fire-time. Authentication's elaborate workaround (override `broadcast_events` to `[]`, then manually wire three `after_*_commit -> { broadcast_changes }` lines) is no longer needed and has been simplified to the standard pattern. New broadcast specs added to `ProjectMembership` covering all three events, locking in correct behavior and preventing silent regressions.

### Maintenance

- **IDN punycode normalization in `EmailNormalizer`.** The `normalize` method now punycode-encodes the domain part via `Addressable::IDNA.to_ascii`, so `user@bücher.de` and `user@xn--bcher-kva.de` collapse to the same canonical form. Closes the documented limitation called out in v1.4.0. Added `addressable ~> 2.8` as an explicit production dependency (it was already available transitively via capybara/webmock, but those are dev/test-only). Local part is intentionally NOT punycoded — RFC 6531 SMTPUTF8 lets mail servers accept Unicode local parts, and IDNA does not apply there. Conversion is wrapped in a broad rescue that falls back to the unencoded domain for malformed inputs (empty labels, double-encoded values), since validation belongs at the model layer.

### Security

- **Per-recipient email throttle** (`app/lib/email_recipient_throttle.rb`). Caps how many emails of a given kind a single recipient address receives across all senders within a sliding window — orthogonal to the per-user `rate_limit` declarations that already gate controller actions. Default policy: 3 sends per recipient per kind per hour, fail-open on cache miss. Closes the gap where N attackers (or one attacker cycling accounts) could each stay under their per-user limit while collectively flooding one victim's inbox. Counter lives in `Rails.cache` (Solid Cache) keyed by SHA-256 of the canonical (NFC + downcase + strip) email plus the kind, so case/whitespace/encoding variants share a bucket. Independent buckets per kind so a flood of one type doesn't suppress legitimate sends of another. Gated callsites: every `AuthenticationMailer.link_verification_email` dispatch in `OmniauthCallbacksController` (re-OAuth on pending, signed-in mismatched-email link, unverified-email new-user) and `Account::ConnectedAccountsController#resend_verification`, plus the new `collision_alert` dispatch.
- **Cross-user OAuth collision alert** (`AuthenticationMailer#collision_alert`). When `OmniauthCallbacksController` detects that a `provider+uid` pair is already linked to a different user (someone else's verified OAuth identity), the legitimate owner now receives a defense-in-depth notification email so they're aware a third party tried to attach their sign-in method to a different ModelRails account. The email explicitly states the user's account is unaffected (does not imply breach) and links to the connected accounts page. Throttled by the per-recipient throttle (`kind: :collision_alert`, separate bucket from verification) so an attacker can't weaponize the alert into a flood. New I18n keys under `authentication_mailer.collision_alert` in `config/locales/en/mailers.en.yml`; HTML and text templates follow the existing `link_verification_email` styling pattern.

### Accessibility

- **WCAG 2.2 Level AAA contrast pass.** Bumped six color tokens to meet 7:1 contrast across light and dark modes:
  - **Light mode:** `--color-danger` (red-700 → red-800), `--color-success` (green-700 → green-900, yellows pass at lower L), `--color-warning` (amber-700 → amber-900), `--color-info` (sky-700 → sky-900), `--color-text-muted` (slate-600 → slate-700, same as body).
  - **Dark mode:** `--color-text-muted` (slate-400 → slate-300, same as body), `--color-interactive` (primary-400 → primary-300; matching adjustments on hover/focus).
  - The "muted" token now has the same darkness as "body" in both modes — visual hierarchy comes from font-size/weight rather than color, since AAA's 7:1 floor leaves little room for two distinct foreground shades on a single surface.
- **Promoted axe-core CI hook from `wcag2aa` to `wcag2aaa`.** Every system spec's automatic accessibility audit now runs at AAA, catching regressions that the prior AA-only audit silently allowed. The `playwright_accessibility.rb` failure output also now includes the full `failureSummary` from each violation (computed contrast ratio, foreground/background hex, font size and weight) — much faster to diagnose AAA contrast misses than the prior bare element dump.
- Fixed a phantom class in `app/views/shared/_a11y_sim.html.erb` (`bg-interactive-surface` → `bg-interactive-subtle`). The non-existent token caused active-state items to inherit the focus state's gray background, which dropped contrast against `text-interactive` to 6.85:1.

---

## v1.4.0 — OAuth Hardening & Design System Primitives v2 (2026-04-28)

### Security

- Email normalization for storage and equality comparison now uses Unicode NFC + downcase + strip via a new `EmailNormalizer` module (`app/lib/email_normalizer.rb`). The `User` model's `normalizes :email_address` and `:pending_email` declarations route through it, so all `find_by` lookups and writes get canonical form (Rails 7.1 auto-applies normalizers to lookup values). The OAuth callback's "OAuth email matches user's primary email" check uses `EmailNormalizer.equivalent?` so an email like `café@example.com` matches itself across NFC vs NFD encodings — previously these would compare as different bytes despite being visually identical, forcing international users through email verification on every OAuth sign-in. Gravatar SHA-256 hashing also uses canonical form so the same email always produces the same Gravatar URL regardless of input encoding. IDN punycode conversion (e.g., `bücher.de` ↔ `xn--bcher-kva.de`) is NOT handled — explicitly deferred until a real interop concern surfaces; would require an addressable-style gem.
- `Authentication#generate_verification_token!` now retries up to 3 times on `ActiveRecord::RecordNotUnique` (defensive against the astronomically-unlikely 256-bit token collision). The `Account::ConnectedAccountsController#resend_verification` action also rescues `RecordNotUnique` at the request level — if every regenerated token still collides, users see a graceful "try again" alert instead of a 500 error.
- OAuth callbacks now check `auth_hash.info.email_verified` before auto-verifying or auto-linking. When an OAuth provider explicitly reports the email as unverified (Google's `info.email_verified: false` for unverified Google accounts), `OmniauthCallbacksController` no longer (a) auto-verifies a newly-linked authentication for a signed-in user even when the OAuth email matches the user's primary email, (b) auto-links a brand-new OAuth signup to an existing verified user account by email match, or (c) auto-verifies and signs in a fresh user from OAuth — instead, the new user is created with a pending authentication and a verification email is sent without signing them in. Closes the account-takeover surface where an attacker could create an unverified Google account using a victim's email and have the app auto-link the OAuth identity to the victim. Providers that don't expose `info.email_verified` (e.g., GitHub) are treated as implicitly verified — only an explicit `false` triggers the gate, preserving existing GitHub OAuth behavior.

### Added

- Design system primitives v2: semantic spacing tokens (`--space-section-gap`, `--space-row-padding`, `--space-action-group-gap`, `--form-input-height`) defined in `app/assets/tailwind/tokens/_spacing.css`. Tokens are CSS-var-only — never registered in `@theme` so they don't leak as Tailwind utility classes. Consumed inside `@layer components` rules and `TailwindFormBuilder` constants.
- Component utilities under a new `@layer components` block in `app/assets/tailwind/application.css`: `.btn-touch-target` (44×44 minimum, reads `--form-input-height`), `.btn-text` (font-weight/underline/focus-visible base), `.btn-text-danger` and `.btn-text-interactive` (color variants), `.action-group` (inline-flex with `--space-action-group-gap`).
- Layout utility `.page-container` (`max-w-2xl mx-auto px-4`) for narrow page wrappers — settings, account, and form-centric flows.
- `docs/design-system.md` — single-source reference for the spacing convention, semantic tokens, component utilities, class ordering convention, and migration recipe. Linked from README.md.

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
- Design doc and implementation plan preserved at `docs/superpowers/specs/2026-04-25-verified-oauth-account-linking-design.md` and `docs/superpowers/plans/2026-04-25-verified-oauth-account-linking.md`

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
- Design doc and implementation plan preserved at `docs/superpowers/specs/2026-04-22-footer-cohesion-design.md` and `docs/superpowers/plans/2026-04-22-footer-cohesion.md`

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
