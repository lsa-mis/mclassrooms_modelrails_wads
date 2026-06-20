---
title: Extending
description: How to add resource types, custom roles, and new features to ModelRails
keywords: resource types roles permissions migration polymorphic customization logo branding cookies gdpr consent analytics
audience: [guide, technical]
---

# Extending ModelRails

## Adding a workspace-scoped feature

Most features you build are **workspace-scoped**: data a tenant owns that must never leak across workspaces. The framework keeps that **explicit** — there is no magic `default_scope` — so you opt in deliberately at each step. Here is the full path for a new model (say, a `Milestone`).

### 1. Generate the model and run the migration

```bash
rails generate model Milestone name:string workspace:references
rails db:migrate
```

`rails generate model` only *writes* the migration; `rails db:migrate` applies it. Skipping the second command is the most common first mistake.

### 2. Decide how it is tenant-scoped

Two shapes — picking the wrong one is the most common *design* mistake:

- **A workspace-level root** (a top-level thing a workspace owns, like `Project`) → `include Tenanted`, which adds `belongs_to :workspace` and a `for_current_workspace` scope.
- **A child of something already tenant-scoped** (e.g. a `Comment` on a `Project`) → just `belongs_to :project`. Do **not** add `Tenanted` or a `workspace_id`; it inherits its tenant transitively through the parent. This is exactly why `Resource` and `Document` carry no `workspace_id` — they reach the workspace via `resource → project → workspace`.

```ruby
# app/models/milestone.rb — a workspace-level root
class Milestone < ApplicationRecord
  include Tenanted   # adds belongs_to :workspace + the for_current_workspace scope
  belongs_to :created_by, class_name: "User"
  validates :name, presence: true
end
```

> **Scoping is explicit, not automatic.** `Tenanted` deliberately installs **no** `default_scope`. You scope every query yourself (step 3). That avoids `default_scope`'s action-at-a-distance, but it means *you* are responsible for never loading a tenant model unscoped.

### 3. Controller — scope through the workspace, and authorize

Include `WorkspaceScoped` (it resolves `@workspace` from the URL slug and sets `Current.workspace`), then query **through the association** — never `Milestone.all`:

```ruby
# app/controllers/workspaces/milestones_controller.rb
class Workspaces::MilestonesController < ApplicationController
  include WorkspaceScoped

  def index
    authorize Milestone
    @milestones = @workspace.milestones.kept   # scoped via the association
  end

  def create
    authorize Milestone
    @milestone = @workspace.milestones.build(milestone_params)
    @milestone.created_by = Current.user
    # ...
  end
end
```

`@workspace.milestones` is the load-bearing isolation boundary; `Current.workspace` (set by `WorkspaceScoped`) is the defense-in-depth backstop that policies and `for_current_workspace` rely on.

### 4. Authorize with a Pundit policy

Every controller action calls `authorize`. Add a policy that extends `ApplicationPolicy`, which provides `membership` (the current user's membership in `Current.workspace`) and `can?("permission")` (reads that member's role-permission flags):

```ruby
# app/policies/milestone_policy.rb
class MilestonePolicy < ApplicationPolicy
  def index?
    membership.present?            # any member of the workspace
  end

  def create?
    can?("manage_projects")        # gated on a role permission
  end

  def update?
    create?
  end

  def destroy?
    record.created_by == user || can?("manage_workspace")
  end
end
```

The permission keys (`manage_projects`, `manage_members`, `manage_workspace`, …) live on each role; see [Workspace Administration](/docs/workspaces) for the full list.

### 5. Opt into shared behavior (optional)

Mix in the same concerns the built-in models use, only as needed:

| Concern | Gives you | Requirement |
|---|---|---|
| `Discardable` | Soft delete (`discard!`, `.kept` scope) | — |
| `Trackable` | Activity-log entries when the record changes | — |
| `Broadcastable` | Turbo Stream broadcasts on change | define a private `broadcast_target` (e.g. `workspace` or the parent record) |

`Project` includes all three; `Resource` broadcasts to its `project`. Copy whichever match your model.

## Adding a New Resource Type

The Resource registry uses a polymorphic pattern. To add a new type (e.g., `Slideshow`):

### 1. Create the model

```bash
rails generate model Slideshow
rails db:migrate          # generate writes the migration; this applies it
```

```ruby
# app/models/slideshow.rb
class Slideshow < ApplicationRecord
  has_one :resource, as: :resourceable, dependent: :destroy
  has_many :slides, dependent: :destroy
end
```

A resource type is reached through `resource → project → workspace`, so it needs **no** `workspace_id` and does **not** `include Tenanted` — see [Adding a workspace-scoped feature](#adding-a-workspace-scoped-feature) for when a model does.

### 2. Register the type

In `app/models/resource.rb`, add to the allowlist:

```ruby
ALLOWED_RESOURCEABLE_TYPES = %w[Document Slideshow].freeze
```

### 3. Create view partials

```
app/views/workspaces/projects/resources/types/_slideshow.html.erb
app/views/workspaces/projects/resources/types/_slideshow_form.html.erb
```

The controller automatically renders the correct partial based on `resourceable_type`.

### 4. Add strong parameters

In `ResourcesController#resourceable_params`, add a case:

```ruby
when "Slideshow"
  params.fetch(:slideshow, {}).permit(:title, slides_attributes: [:image, :caption, :position])
```

## Customizing the Site Logo

The app logo is rendered via `app/views/shared/_site_logo.html.erb`, an inline SVG partial used in both the header and footer. It accepts strict locals:

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `size` | `:medium` | SVG height — `:small` (h-6), `:medium` (h-8), `:large` (h-10) |
| `color_class` | `"text-sky-700"` | Tailwind color class for the SVG mark (uses `currentColor`) |
| `show_name` | `false` | Show the app name text next to the mark |
| `name_class` | `"text-xl font-bold text-slate-900 dark:text-gray-100"` | Tailwind classes for the name text |

To replace the logo with your own SVG, edit the partial and swap the `<svg>` content. Keep `aria-hidden="true"` and `fill="currentColor"` so theming and accessibility continue to work.

Usage example:

```erb
<%= render "shared/site_logo", size: :small, show_name: true %>
```

## Cookie Consent (GDPR)

The app includes a GDPR cookie consent banner via [biscuit-rails](https://github.com/garethfr/biscuit-rails). It renders at the bottom of every page and manages consent across 4 categories:

| Category | Required | Purpose |
|----------|:--------:|---------|
| `necessary` | Yes | Session, CSRF, theme preference |
| `analytics` | No | Usage tracking (Google Analytics, etc.) |
| `preferences` | No | Non-essential preference cookies |
| `marketing` | No | Advertising and retargeting pixels |

Configuration is in `config/initializers/biscuit.rb`. The engine is mounted at `/biscuit`.

### Guarding third-party scripts

Wrap any non-essential scripts with the `biscuit_allowed?` helper:

```erb
<% if biscuit_allowed?(:analytics) %>
  <script async src="https://www.googletagmanager.com/gtag/js?id=G-XXXXXX"></script>
<% end %>

<% if biscuit_allowed?(:marketing) %>
  <!-- Retargeting pixel -->
<% end %>
```

In controllers:

```ruby
Biscuit::Consent.new(cookies).allowed?(:analytics)
```

### Disabling the banner

If your deployment only uses functional cookies (session, theme, CSRF), you can remove the banner by deleting `<%= biscuit_banner %>` from both layouts.

## Invitation Types

The invitation system supports two modes:

- **Email invitations** — enter email addresses, system sends invitation emails with 7-day expiry tokens
- **Magic link invitations** — generate a shareable URL (no email needed), useful for posting in Slack or team docs

Both types create the same `Invitation` record. The difference is whether `email` is present. See [Workspace Administration](/docs/workspaces) for full details.

## Adding Custom Workspace Roles

Seed a new role with custom permissions:

```ruby
# db/seeds.rb
Role.find_or_create_by!(slug: "billing_admin", workspace_id: nil) do |r|
  r.name = "Billing Admin"
  r.permissions = { manage_settings: true, manage_billing: true }
end
```

Then check the permission in policies:

```ruby
def manage_billing?
  can?("manage_billing")
end
```

## Upgrading Project Roles to Role Model

If you need custom project roles beyond creator/editor/viewer:

1. Add `role_id` to `project_memberships`: `rails generate migration AddRoleIdToProjectMemberships role:references`
2. Seed project-specific roles with a `context` column on Role
3. Update `ProjectMembershipPolicy` to use `can?` instead of enum checks
4. Migrate existing data: map enum values to Role records

## Adding Per-Resource Permissions

For fine-grained access (e.g., "can view Document A but not Document B"):

1. Create a `ResourceShare` model: `user_id`, `resource_id`, `permission` (read/write)
2. Update `ResourcePolicy` to check both project membership AND resource shares
3. Resources without shares fall back to project-level permissions

## Project Tools registry

Each project carries a set of tools (tabs in the project navigation). The base template ships `:docs` only. Forks add tools by registering them in `config/initializers/project_tools.rb` **after** building the tool's surface (model + controller + routes + views):

```ruby
# config/initializers/project_tools.rb
Rails.application.config.to_prepare do
  ProjectTools::Registry.reset!

  # Built-in tool — keep this.
  ProjectTools::Registry.register(
    key: :docs,
    path_helper: :workspace_project_resources_path,
    default_enabled: true
  )

  # Your tool — register it here.
  ProjectTools::Registry.register(
    key: :messages,
    path_helper: :workspace_project_messages_path,
    default_enabled: true
  )
end
```

`path_helper` is a project-scoped route helper the project tab bar calls as `helper(workspace, project)`.

Gate a tool's controller so its routes redirect back to project home when the tool is disabled for that project:

```ruby
class Workspaces::Projects::MessagesController < ApplicationController
  include WorkspaceScoped
  include EnforcesProjectTool
  enforces_tool :messages          # redirects if tool_enabled?(:messages) is false

  before_action :set_project       # must run BEFORE the EnforcesProjectTool guard
  # …
end
```

The `EnforcesProjectTool` concern reads `@project.tool_enabled?(key)`, so `set_project` must populate `@project` before the guard fires. See [Project Tools](/docs/project-tools) for the full how-to.

## Clientside (external-client area)

The Clientside subsystem lets managers share a read-only project view with external clients — without giving them workspace membership or a seat in workspace policies.

Key extension points:

- **Enable per project.** Clientside is toggled on a per-project basis via the project's Clientside settings (`Workspaces::Projects::ClientsidesController`, `edit_workspace_project_clientside_path`). A project must have `clientside_enabled?` returning `true` before any client-invite or access logic runs.
- **Invite a client.** `Invitation.invite_client!(project:, email:, company_name:, invited_by:)` creates a client-type invitation and dispatches the invite email. The invitation form lives at `new_workspace_project_client_invitation_path` (`Workspaces::Projects::ClientInvitationsController`).
- **Acceptance creates a `ClientAccess`.** When a client accepts via `GET /invitations/:token/accept` (or `POST` if already signed in), `Invitation#accept_client_invitation!` creates a `ClientAccess` row — a deliberate non-`Membership` record so clients never enter workspace policies or member-seat counting.
- **Client area controllers.** `Clientside::BaseController` (namespace `clientside`) resolves projects only through `Current.user.client_accesses.kept` — clients cannot reach workspace-scoped resources. `Clientside::ProjectsController` lists accessible projects; `Clientside::Projects::ResourcesController` shows individual resources that are `client_visible?`. The layout is `clientside`, isolated from the workspace shell.
- **`skip_onboarding_requirement`.** `Clientside::BaseController` calls `skip_onboarding_requirement` so that client users (who have no workspace and therefore no `onboarded_at`) land in the client area rather than being funnelled into the onboarding wizard.

See [Clientside](/docs/clientside) for the full configuration and usage guide.

## Next steps

- **[Architecture](/docs/architecture)** — the request flow, tenancy model, and key directories your new code plugs into.
- **[Deployment](/docs/deployment)** — ship it with Kamal once your feature is built.
- Browse the full **[docs index](/docs)** for feature-specific references (workspaces, notifications, identity, background jobs).
