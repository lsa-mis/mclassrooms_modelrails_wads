---
title: Clientside
description: External client access to a project — the ClientAccess model, per-project Clientside toggle, resource sharing, client invite flow, and the read-only client area.
keywords: clientside client access external ClientAccess project sharing resource invite company company_name client area read-only
---

# Clientside

Clientside lets a team share selected project resources with an external client. The client is a regular `User` who sees a focused, read-only area — they never enter workspace policies and consume no member seat.

> See the enable → share → invite → client-area flow drawn as a wireframe in [Application Flows](/docs/developer/application-flows).

## Data model

`ClientAccess` (`app/models/client_access.rb`) is the join record between a `User` and a `Project`:

- `belongs_to :project` and `belongs_to :user`
- `include Discardable` — soft-deletable; a discarded access is treated as revoked
- `company_name` (required)
- `validates :user_id, uniqueness: { scope: :project_id }` — one access record per user per project
- `validate :project_clientside_enabled, on: :create` — raises if Clientside is not enabled on the project at creation time

Convenience predicates:

- `Project#client?(user)` — `client_accesses.kept.exists?(user: user)`
- `User#client_of?(project)` — available via the `has_many :client_accesses` association

Clientside access is intentionally **not** a `Membership`. Clients never appear in workspace member lists, never consume a seat counted by `Workspace#max_members`, and are invisible to workspace-scoped Pundit policies.

## Enabling Clientside on a project

Each project has a `clientside_enabled` boolean (default `false`). Team members with project update permission toggle it via `Workspaces::Projects::ClientsidesController` (edit/update), reachable at the project's Clientside settings page.

## Sharing resources with a client

`Resource` gains a `shared_with_client` boolean. The team checks "Share with the client side" on a resource's edit form (the checkbox is only shown when Clientside is enabled on the project).

- `Resource#client_visible?` — `shared_with_client? && published?`
- `Project#client_visible_resources` — `resources.kept.published.where(shared_with_client: true).positioned`

A resource must be both shared **and** published to appear in the client area.

## Inviting a client

`Invitation` supports a client variant. A client invite is identified by a non-blank `company_name`:

- `Invitation#client_invite?` — `company_name.present?`
- Role is not required on a client invite (`validates :role, presence: true, unless: :client_invite?`)
- `Invitation.invite_client!(project:, email:, company_name:, invited_by:)` creates the invitation and queues `InvitationMailer#invite_client`

Client invitations are sent from `Workspaces::Projects::ClientInvitationsController` (`new`/`create`), which requires `manage_members` permission and verifies Clientside is enabled before rendering.

### Acceptance

When a client invite is accepted (`Invitation#accept_client_invitation!`):

1. Confirms Clientside is still enabled on the project.
2. Creates a `ClientAccess` (or undiscards an existing discarded one).
3. Stamps `user.onboarded_at` unless the user is already onboarded.

The `consume!` bearer-token guard (`EmailMismatch`) is reused — a leaked link cannot be redeemed by a different email address.

**Existing user** accepting a client invite → one-click → lands in the client area.

**New email** → sets up a login → client area.

## Client area

The `Clientside::` controller namespace hosts the read-only client experience:

- **`Clientside::BaseController`** — inherits from `ApplicationController`; calls `skip_onboarding_requirement`; uses `layout "clientside"`; does **not** include `WorkspaceScoped` and never sets `Current.workspace`. All project access is resolved through the user's own `client_accesses`.

  `set_client_project` resolves the slug **within** the user's own accessible projects (their kept `ClientAccess` set) — slug knowledge alone grants nothing — and then applies the lifecycle predicate `Project#client_accessible?`. A project is client-accessible only while it and its workspace are kept and the workspace is not locked; an **archived** project or workspace stays accessible (archived keeps existing collaborators). Anything else redirects with a generic no-access message that never reveals the project's or workspace's lifecycle state.

  `ensure_clientside_enabled` redirects away if the project's Clientside has been turned off after the access was granted.

- **`Clientside::ProjectsController`**
  - `index` — lists the projects the user has a kept `ClientAccess` for, filtered through `Project.client_accessible` (archived-workspace projects still appear; deleted or locked ones don't)
  - `show` — renders `@project.client_visible_resources` (read-only)

- **`Clientside::Projects::ResourcesController`**
  - `show` — renders a single resource, gated by `Resource#client_visible?`

## Routing client-only users home

`authenticated_home_path` (in `Authenticatable`) routes a user to `clientside_projects_path` when they have at least one kept `ClientAccess` and **no** kept workspace `Membership`. Users who also have workspace memberships land on `root_path` as normal.

```ruby
def authenticated_home_path
  user = Current.user
  if user && user.client_accesses.kept.exists? && user.memberships.kept.none?
    clientside_projects_path
  else
    root_path
  end
end
```

## Security boundary

- A client can only see resources on a specific project they have been explicitly invited to.
- Revoking access (discarding the `ClientAccess`) immediately stops the client from reaching that project — `set_client_project` finds no kept access and redirects.
- Disabling Clientside on a project (`clientside_enabled: false`) blocks all client access to that project via `ensure_clientside_enabled`, even if `ClientAccess` records still exist.
- Clients operate under the `clientside` layout with no workspace context — workspace data, member lists, and workspace settings are never in scope.

## Fork seams

- **Additional client-area pages** — add controllers under `Clientside::` inheriting from `Clientside::BaseController`.
- **Richer client profiles** — add columns to `client_accesses` and surface them in the invite flow.
- **Client notifications** — wire notifiers scoped to the client's `ClientAccess`.

See [/docs/projects](/docs/user/projects) for the workspace-side project model and [/docs/security](/docs/developer/security) for the broader authentication and authorization posture.
