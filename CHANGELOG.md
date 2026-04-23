# Changelog

All notable changes to ModelRails are documented here, organized by phase.

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
- mise-based version management via .tool-versions
