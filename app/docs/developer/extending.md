---
title: Extending
description: How to add tenant-scoped models, custom roles, and new features to ModelRails
keywords: tenanted roles permissions migration customization logo branding cookies gdpr consent analytics
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

- **A workspace-level root** (a top-level thing a workspace owns, like a `Milestone`) → `include Tenanted`, which adds `belongs_to :workspace` and a `for_current_workspace` scope.
- **A child of something already tenant-scoped** (e.g. a `Comment` on a `Milestone`) → just `belongs_to :milestone`. Do **not** add `Tenanted` or a `workspace_id`; it inherits its tenant transitively through the parent.

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

The permission keys (`manage_projects`, `manage_members`, `manage_workspace`, …) live on each role; see [Workspace Administration](/docs/user/workspaces) for the full list.

### 5. Opt into shared behavior (optional)

Mix in the same concerns the built-in models use, only as needed:

| Concern | Gives you | Requirement |
|---|---|---|
| `Discardable` | Soft delete (`discard!`, `.kept` scope) | — |
| `Trackable` | Activity-log entries when the record changes | — |
| `Broadcastable` | Turbo Stream broadcasts on change | define a private `broadcast_target` (e.g. `workspace` or the parent record) |

Workspace and Membership already use all three; copy whichever match your model.

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

Both types create the same `Invitation` record. The difference is whether `email` is present. See [Workspace Administration](/docs/user/workspaces) for full details.

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

## Next steps

- **[Architecture](/docs/developer/architecture)** — the request flow, tenancy model, and key directories your new code plugs into.
- **[Deployment](/docs/developer/deployment)** — ship it with Kamal once your feature is built.
- Browse the full **[docs index](/docs)** for feature-specific references (workspaces, notifications, identity, background jobs).
