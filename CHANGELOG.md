# Changelog

All notable changes to ModelRails are documented here, organized by phase.

## [Unreleased]

### Breaking

- `config/deploy.yml` `servers.web` schema changed from a flat host list to a `hosts:` + `options:` form to support `max-replicas: 1` (#135). Forks that customized `deploy.yml` between v1.4.0 and now must update the structure — see the migration note in `app/docs/deployment.md`.
- Email verification switched to signed, stateless tokens (`Authentication.generates_token_for :email_verification`); dropped the `authentications.verification_token` and `verification_sent_at` columns and unique index (#178). Verification and OAuth-link confirmation links issued before upgrade stop working.

### Security

- Invitation acceptance is now bound to the invited email across every path — new-user signup, OAuth, magic-link, and signed-in accept — and deferred until that email is verified. A leaked invite link can no longer be redeemed by someone else, even from a different verified or signed-in account (#175, #176). Magic-link invitations remain intentionally bearer.

### Changed

- Retired the deferred "personal workspace"/"personal profile" settings copy → "your workspace" (the tenant) / "your profile" (identity); the personal settings section label "Account" → "You" (honest-naming, identity/tenant split).
- Removed the half-wired dynamic-PWA scaffold (#306): the unused `app/views/pwa/manifest.json.erb` + `service-worker.js` and their commented-out routes are gone. The working static `public/manifest.webmanifest` stays (its name already matches `brand.en.yml`), so the fork-rename checklist now points at one manifest instead of two.
- Fork-readiness code-quality cleanup (#305): policies resolve the project via `respond_to?(:project)` instead of class checks; new-device detection rescues only `ActiveRecord::ActiveRecordError` so genuine bugs surface instead of being swallowed; activity-tracking failure logs now name the record (`Class#id`).
- `.env.example` now documents every operator-settable ENV var the code reads (was 3 of ~18), grouped by scope — Rails, Kamal, server tuning, signup gating, tenancy preset, and shared-preset seeds — each with its default/valid-values and a pointer to the relevant `app/docs` page (#298). A new template invariant greps the codebase for `ENV[...]`/`ENV.fetch` and fails if any operator-settable var is missing from `.env.example`, so it can't silently drift again.
- SQLite `journal_mode: wal` is now declared explicitly in `config/database.yml` rather than relying on the Rails 8.1 adapter default, so a fork reads the production durability/concurrency posture in the config instead of inferring it (#304). `pragmas:` merges over Rails' defaults, so `synchronous: normal`, `foreign_keys`, `mmap_size`, etc. are preserved. Documented that `timeout: 5000` installs a Ruby busy handler (writers wait 5s) — `PRAGMA busy_timeout` reads 0 by design, and a runtime spec pins that so nobody "fixes" it into replacing the handler.
- CI lint tooling is now version-pinned (#299): `markdownlint-cli` and `@herb-tools/linter` moved from unpinned `npm install -g` into `package.json` devDependencies (lockfile-pinned), invoked via `npx` so CI, local pre-push (Lefthook), and every fork run the identical linter. `bin/setup` now runs `npm ci`. Removed `--ensure-latest` from `bin/brakeman` — it failed CI the moment a newer brakeman shipped, on every branch with no code change (the drift behind #319). Same anti-drift principle applied across npm and Ruby tooling.
- Unified the UI signal vocabulary to a canonical `info·success·warning·danger` ladder (`destructive`/`error` kept as non-breaking aliases); alert gains all four levels and badge signal chips move from solid base-token fills to tinted surfaces, fixing the low-contrast muddy-brown warning badge. Indicator `warning` count text moved off the non-adaptive `text-text-heading` to the adaptive `text-text-on-interactive`.
- Avatar notification indicator restored as a severity-colored dot (v2 — supersedes D1's split). Avatar carries the dot on desktop; hamburger button on mobile. Standalone header bell removed; the in-menu Notifications row is the canonical triage entry point. Live updates target three new frames (`notifications_indicator_avatar`, `notifications_indicator_hamburger`, `notifications_menu_count_frame`) plus the aria-live region. AAA contrast preserved via `--color-danger-strong` (the project's graphic-accent token).
- Email/password signup defers invitation acceptance — the pending invitation is parked on the new email authentication and claimed when the email is verified, rather than granted at signup (#175).

### Accessibility

- Quiet-hours empty-days warning now sits in a stable `role="status"` / `aria-live="polite"` wrapper instead of carrying the live-region role on the element that toggles `display:none`. A live region that itself flips to `display:none` pops in/out of the accessibility tree and announces unreliably; keeping the wrapper always present means revealing the warning is spoken to screen readers (closes #302).
- `autocomplete="off"` on the read-only join-link copy field (`workspaces/settings/_join_policy_section`), clearing the `html-input-require-autocomplete` warning the newly-pinned herb-lint (#299) surfaced.

### Added

- Add first-run onboarding journey (none posture): name workspace → first project → invite, with a soft email-verification gate.
- `:none` onboarding posture (`WORKSPACE_ON_SIGNUP=none`) — signup creates no workspace; identity lives at the User level; workspaces are created or joined through explicit product flows. Pairs with an overridable `authenticated_home_path` private method that every post-auth path routes through (sessions, magic-link, OAuth, registrations, `redirect_if_authenticated`); forks override one method to land users on a workspace-agnostic home. See `app/docs/presets-none.md` (#343).
- Fork-owned brand-color seam: `app/assets/tailwind/tokens/_brand.css` (`merge=ours`, imported after `_primitives.css`) lets a fork swap its primary palette family without editing the template-owned defaults or hitting merge conflicts — the color twin of `brand.en.yml`. Ships empty (zero compiled bytes); see `docs/theming.md` (#313).
- Deployment docs: Thruster's automatic X-Sendfile offload documented with an explicit "don't configure `x_sendfile_header`" guard (breaks non-Thruster deploys), plus a health-check-timeout troubleshooting entry.
- `bin/deploy-guide` — target-aware deployment guidance (kamal / self-host / managed), plus a "Deploying without Kamal" portable-contract section in `app/docs/deployment.md` for Hatchbox-style platforms.
- Lookbook component explorer at `/lookbook` (development-only) for the vendored `UI::*` components — `modelrails_ui` upgraded to v0.2.0 plus the `lookbook` gem; preview classes live in `spec/components/previews`.
- Vendored `UI::*` ViewComponents (button, input, textarea, file_input, dialog, avatar) via the dev-only `modelrails_ui` scaffolding gem; the form-field builder, `shared/_modal`, and `avatar_for` delegate to them with no rendered-output change — `view_component` is a runtime dependency, `modelrails_ui` is development-only.
- Appearance destination time-zone picker — explicit `override=true` submit to `Account::Preferences::TimezonesController#update`; the existing browser beacon's write-on-blank guard preserves the explicit choice on subsequent visits (closes #154).
- Settings hub destinations: disambiguated H1s + descriptions on each sidebar destination, shared `shared/_settings_page_header.html.erb` partial, and Appearance page (closes #150 — sidebar link no longer 405s).
- Settings hub mobile drawer: hamburger toggle below 768px slides the sidebar in as an off-canvas drawer with overlay, focus trap, ESC + click-outside dismiss, and auto-close on sidebar navigation (closes #148).
- Settings hub shell: sidebar-equipped layout (`layouts/settings.html.erb`) for account- and workspace-tier settings, with context-adaptive item list, Pundit-gated visibility, polite aria-live region, and site-wide Turbo morph.
- Personal-workspace OKLCH context ramp via `[data-workspace-kind="personal"]` — desaturated slate treatment so solo users see a deliberate visual identity rather than unstyled-org defaults.
- Chroma-boosted color swatch on org workspaces in the sidebar switcher — small vertical chip beside each workspace name using its `primary_color` for at-a-glance differentiation.
- Notifications v1 — in-app bell + dropdown, dedicated `/account/notifications` triage page, real-time arrival broadcasts, preferences UI (DND, 5×3 category/channel matrix, digest cadence, retention), email digests every 15 minutes, and 10 wired notifier types covering workspace, project, billing, and security events (#48, #53–#56, #64–#71).
- Optional VS Code Dev Container that matches the production image (#129).
- `.env.example` documenting required environment variables (#129).
- YJIT enabled in production (#129).
- CI builds the production Docker image on every PR (#134).
- New deployment, background-jobs, and dev-environment docs at `/docs` (#136).
- A clear notice when an invitation was addressed to a different email than the one being used — shown on verification, on signup, and on signed-in accept, instead of failing silently (#177, #180).
- **Single-tenant preset** (`WORKSPACE_ON_SIGNUP=shared`) — one shared workspace, no personal workspaces, tenancy UI suppressed. Setup is env-driven with a seed that bootstraps the workspace + initial Owner and mails a password-set link. See `app/docs/presets.md`.
- **Per-workspace `join_policy`** (`invite` or `open_link`) with `WorkspaceJoinLink` (`has_secure_token`, revocable, atomically rotatable). Settings UI surfaces the radio + copy/rotate/revoke under `/workspaces/:slug/settings/edit`. Both join flows are wired: **Flow A** (existing authenticated user joins via link) and **Flow B** (new user → link opens the signup gate under `:invite_only`, token parked on the email auth, claimed at email verification). Instance ceiling via `SIGNUP_PERMITTED_JOIN_STRATEGIES` (default `invite`); personal workspaces are hard-guarded. Membership grants consolidate into `Workspace#admit`. See `app/docs/presets.md` (Open SaaS) and `app/docs/workspaces.md` (Join Policies).
- Fork seams for downstream apps: brand strings in fork-owned `config/locales/en/brand.en.yml`, product routes in `config/routes/app.rb` via `draw(:app)`, `/docs` categories extendable through `config/markdowndocs_categories.local.yml`, and fork-owned paths marked `merge=ours` in `.gitattributes` (driver auto-activated by `bin/setup` in forks).
- In-app forking guide at `/docs/forking` — start a downstream app, rename the identity, pull upstream updates; the README forking section now points there.

### Bug fixes

- Settings-hub Turbo morph is now actually active (#327). `turbo_refreshes_with method: :morph` buffers its meta tags into `:head` via `provide`, but neither layout had a `yield :head` to render them, so the morph meta never emitted and the hub silently fell back to `replace`. The shared `_layout_head` now yields `:head` and the settings layout provides the morph meta before it renders — the announcer dedup and idiomorph-safe switcher IDs were already built for this.
- Single-tenant preset: invitation-driven signups now adopt the invitation's role instead of being stuck at the `onboard_workspace` callback's placeholder Member. Solo-default (`:personal`) semantics are unchanged.
- Unauthenticated invitees can accept invitations under invite-only signup — the accept page stashes the pending invitation token so the signup gate opens (#345).
- Development mailer URLs now follow the running `PORT`, so letter_opener links work on non-default ports (#346).

### Changed

- `TENANCY_ONBOARDING` renamed to `WORKSPACE_ON_SIGNUP` — the new name asks "which workspace does a new user land in at signup?", making `none` read honestly (the app is always multi-tenant) rather than implying no tenancy.
- Sidebar skips the personal-only `memberships` eager-load unless onboarding is `:personal` — dead weight under `:none`; `docs/deprecations.md` documents the `personal?` branching as a presentation leak (#344).
- Workspaces index (`/workspaces`) rewritten from a phonebook into a workbench per Jason Fried's "weak index" critique. Pinned-current row (by most-recently-accessed) with CURRENT badge; "Other workspaces" section sorted by `memberships.last_accessed_at DESC NULLS LAST, name ASC`. Each row carries plan badge, role badge, member count (from preloaded relation, no counter cache), last-accessed timestamp, Switch + Leave inline verbs (Leave gated by `MembershipPolicy#destroy?` which now permits self-leave under personal-workspace + last-owner safety guards). Adds `memberships.last_accessed_at` column + composite index, plus a `WorkspaceScoped` before_action that touches the timestamp on every workspace-scoped request (single UPDATE per request, silently rescued). Single-membership users see only the pinned section without an "Other workspaces" heading.
- Mobile shell: header now expands accordion-style on mobile to surface the active sidebar contents inline. Replaces the off-canvas drawer pattern shipped earlier this cycle (#148) — one navigation paradigm across breakpoints, no overlay/focus-trap/dialog ARIA, same axe AAA coverage. Workspace-scoped pages and settings pages both use the unified pattern.
- Header workspace switcher hides personal workspaces — solo users feel single-tenant in the header; the personal workspace remains accessible through the Settings hub sidebar switcher, which is the explicit IA surface for workspace-context switching (closes #145).
- Account Profile, Notification Preferences, Connected Accounts (Security), Workspace Settings, and Workspace Members destinations now use the shared settings page header for consistent chrome.
- Smooth motion-safe color transitions on sidebar items and switcher; settings layout's context attribute renamed `data-settings-context-kind` → `data-workspace-kind`; hover prefetch added to header user-menu settings links and header workspace dropdown.
- Route consolidation: `workspaces#edit` now serves the workspace Profile (identity — name, logo, primary_color); `workspaces/settings#edit` narrows to Limits & Plan. Admin sees Profile in sidebar (capability expansion vs pre-consolidation when sidebar gated on Owner-only `WorkspacePolicy#update?`; now gated on `Workspaces::ProfilePolicy#update?` = `manage_settings`).
- Notifications bell is now a standalone header affordance (sibling to the avatar on desktop, sibling to the hamburger on mobile) routing directly to the triage page. The user-menu dropdown collapses to two items: a clickable identity block (avatar + name + email → personal-workspace profile) and sign-out. Notification preferences remains accessible via the Settings hub sidebar's personal-context Notifications item. Renames `notifications_avatar_button_label_frame` → `notifications_bell_label_frame` to match its new home; drops the `notifications_menu_count_frame` broadcast and the `_notifications_menu_count_span` / `_user_menu_avatar_button_label` partials.
- Mobile-accordion sidebar contents flow inline instead of appearing as a nested sidebar. Extracts the switcher + nav items from `_settings_sidebar` and `_workspace_sidebar` into chrome-free `_settings_sidebar_items` / `_workspace_sidebar_items` partials. Desktop column still renders the `<aside>` wrapper with sidebar visual chrome; mobile accordion renders the items partials directly so the menu items flow alongside the identity block and sign-out without a boxed sidebar-inside-a-menu effect — matches the modelrails_agent_os mobile pattern.
- Sidebar items partials gain a visual divider between the workspace switcher and the nav list, plus a context-aware section label (`Account` in personal-context settings, `Workspace` in org-context settings and on workspace pages). Adds `settings.sidebar.section_label.{personal,org}` and `workspaces.sidebar.section_label` locale keys. Visible on both desktop and inside the mobile accordion — matches the agent_os "WORKSPACE" / section-label rhythm.
- Sidebar nav items gain icons (Heroicons v1 outline): Profile → user_circle, Notifications → bell, Security → shield_check, Appearance → color_swatch, Members → user_group, Invitations → envelope, Limits & Plan → chart_bar, Overview → home, Projects → folder, Settings → cog. Adds 8 new SVGs to the icon registry (`app/assets/icons/outline/`); the icon helper auto-discovers them on first reference, no registration step. Icons render via the existing `_settings_sidebar_item` partial's `icon:` local (previously unused).

### Removed

- `settings-drawer` Stimulus controller, `settings.mobile_drawer.*` and `workspaces.mobile_drawer.*` locale namespaces, and the off-canvas drawer markup from `settings.html.erb` and `application.html.erb` — superseded by the header accordion (see Changed).
- `Workspaces::BrandingsController` and its routes (`/workspaces/:slug/branding/*`). Identity picker hub moved to `WorkspacesController#identity_picker_hub` (`/workspaces/:slug/identity_picker_hub`).
- `Workspaces::BrandingPolicy` (replaced by `Workspaces::ProfilePolicy` on workspaces#edit/update).
- Orphan header dropdown partials (`shared/_workspace_switcher.html.erb`, `shared/_navigation.html.erb`) and the unused `navigation.new_workspace` locale key — completes Path Y; the sidebar switcher is the canonical workspace-switching surface.
- Header "Workspaces" text link (desktop + mobile-accordion blocks) and the orphaned `navigation.workspaces` locale key — the sidebar switcher's full workspace list (with "Create workspace" footer) is now the sole workspace-context affordance, eliminating a UX confusion where the literal "Workspaces" link inside the mobile accordion was being tapped as if it were the switcher.

### Bug fixes

- `Broadcastable` concern now respects subclass `broadcast_events` overrides (destroys broadcast as expected on `ProjectMembership`).
- Production `docker build` failure after the Ruby pin change in #129 (#132).

### Maintenance

- Ruby bumped to 4.0.4 and enforced by Bundler across dev, CI, and production (#129).
- Production image is smaller — no longer ships test gems (#129).
- Production deploys constrained to one web container at a time, with longer job-drain window (#135, closes #130).
- Solid Queue uses named queues (`default`, `mailers`, `low`) for observability (#135).
- Faster CI builds on native architectures (parallel bootsnap precompile) (#131).
- IDN punycode normalization in `EmailNormalizer` — canonical-form email comparison across `bücher.de` ↔ `xn--bcher-kva.de` encoding variants.

### Security

- Per-recipient email throttle across senders — orthogonal to per-user `rate_limit` declarations; prevents N attackers from collectively flooding one victim's inbox while each staying under per-user limits.
- Cross-user OAuth collision alert — when an attacker tries to link your verified OAuth identity to a different account, you receive a defense-in-depth notification email (account remains unaffected).

### Accessibility

- WCAG 2.2 Level AAA contrast pass — six color tokens bumped to 7:1 in both light and dark modes; `text-muted` now matches `text-body` so visual hierarchy comes from font-size/weight, not color.
- axe-core CI checks promoted from `wcag2aa` to `wcag2aaa`; failure output enriched with computed contrast ratio, foreground/background hex, and font sizing for faster diagnosis.
- Code blocks at `/docs` meet WCAG 2.2 AAA contrast in both light and dark modes (#137).

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
