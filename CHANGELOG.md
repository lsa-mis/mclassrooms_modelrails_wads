# Changelog

All notable changes to ModelRails are documented here, organized by phase.

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
