---
title: Extending
description: How to add tenant-scoped models, custom roles, and new features to ModelRails
keywords: tenanted roles permissions migration customization logo branding cookies gdpr consent analytics cross-workspace unscoped queries sweep jobs admin rake tasks
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
    can?("manage_settings")        # gated on a role permission
  end

  def update?
    create?
  end

  def destroy?
    record.created_by == user || can?("manage_workspace")
  end
end
```

The permission keys (`manage_settings`, `manage_members`, `manage_workspace`, …) live on each role; see [Workspace Administration](/docs/user/workspaces) for the full list.

### 5. Opt into shared behavior (optional)

Mix in the same concerns the built-in models use, only as needed:

| Concern | Gives you | Requirement |
|---|---|---|
| `Discardable` | Soft delete (`discard!`, `.kept` scope) | — |
| `Trackable` | Activity-log entries when the record changes | — |
| `Broadcastable` | Turbo Stream broadcasts on change | define a private `broadcast_target` (e.g. `workspace` or the parent record) |

Workspace and Membership already use all three; copy whichever match your model.

### 6. Outside the request cycle (jobs, rake tasks, machine clients)

Controllers establish `Current.workspace` for you (`WorkspaceScoped` resolves it from the URL slug); **nothing does that automatically anywhere else**. A job, rake task, or any future non-browser entry point doing tenant-scoped work must set it explicitly — and should read it back with `Current.workspace!` (note the bang), which raises `Current::NoWorkspaceError` when context was never established. The plain `Current.workspace` returns `nil` in that situation, and a `nil` inside a `where` clause silently widens the query across tenants — the exact failure the explicit-scoping design exists to prevent.

```ruby
class DigestJob < ApplicationJob
  def perform(workspace_id)
    Current.workspace = Workspace.find(workspace_id)  # establish explicitly
    Current.workspace!.rooms.find_each { |room| ... } # read with the bang
  end
end
```

## Cross-workspace queries

Everything above scopes to *one* workspace. Some code legitimately needs the
opposite — a query that spans every workspace on purpose: a maintenance
sweep, a retention job, an operator fixing a single account from the command
line. `Tenanted` installs no `default_scope`, so nothing *stops* a query from
crossing workspaces; the question is where it's safe to write one.

### Where it's safe

`spec/code_smells/no_unscoped_tenant_loads_spec.rb` only scans
`app/controllers/`, `app/helpers/`, and `app/views/` — request-context code,
where `Current.workspace` is ambient and a stray class-level
`Room.find(params[:id])` can hand a signed-in user's role in *their*
workspace the authority to act on someone else's record
(`ApplicationPolicy#record_in_current_workspace?` is the runtime backstop for
that case, but the unscoped load itself is the smell the spec fails on).
**Jobs, rake tasks, and the Rails console are outside that scan** — there's
no ambient `Current.workspace` to leak and no signed-in user's permissions to
misapply. That's the boundary: request-context code always scopes through
the workspace (see [Adding a workspace-scoped
feature](#adding-a-workspace-scoped-feature) above); background code whose
whole job is touching many or all workspaces queries the model directly.

### Pattern 1 — iterate every workspace explicitly

`WorkspaceCapacitySweepJob` walks every kept workspace and reads each one's
own associations — never `Current.workspace`, never `for_current_workspace`:

```ruby
# app/jobs/workspace_capacity_sweep_job.rb
Workspace.kept.find_each do |workspace|
  sweep_members_metric(workspace)   # workspace.memberships.kept.count, etc.
end
```

Reach for this shape when the job genuinely means "every workspace" — quota
checks, per-tenant digests, anything that needs each workspace's own scoped
data one at a time.

> **Trap:** don't call `for_current_workspace` from code like this expecting
> "every record." It reads ambient `Current.workspace`, which is `nil`
> outside a request, so the scope silently becomes `where(workspace: nil)` —
> zero rows, not all of them. Query through the workspace association
> instead (`workspace.memberships.kept`), as above.

### Pattern 2 — a global condition, not a tenant identity

Most of the scheduled sweeps in `app/jobs/` (registered in
`config/recurring.yml`) don't iterate workspaces at all. They query the model
directly on a condition that has nothing to do with tenancy — age, status —
so touching every workspace is just what "in batches" naturally does:

```ruby
# ActivityLogRetentionSweepJob — 12-month retention window, no workspace filter
ActivityLog.where(created_at: ...RETENTION_WINDOW.ago).in_batches(of: 100, &:delete_all)

# WorkspaceInvitationExpiringSweepJob — every workspace's expiring invitations at once
Invitation.where(accepted_at: nil, declined_at: nil)
          .where("expires_at BETWEEN ? AND ?", Time.current, 24.hours.from_now)
          .find_each { |invitation| ... }

# DigestMailerJob — User isn't even Tenanted, but the same shape applies
User.joins(:preferences)
    .where("user_preferences.digest_next_due_at <= ?", Time.current)
    .find_each { |user| ... }
```

This is the same class-level-finder shape the request-context spec forbids
in a controller — legitimate here for the same reason as Pattern 1: no
ambient `Current.workspace` to misapply, and the condition doing the scoping
is global by design rather than standing in for "the current workspace."

### Pattern 3 — operator tools resolve one record by its own identifier

`lib/tasks/admin.rake` and `lib/tasks/tenancy.rake` run outside any request
too, so an operator can resolve a single record with a class-level finder —
something the code-smell spec would flag inside a controller:

```ruby
# lib/tasks/admin.rake
user = User.find_by!(email_address: args[:email])
workspace = Workspace.find_by!(slug: args[:slug])
```

It's safe here because there's no signed-in user whose permissions could
misfire against the result — the operator names the target directly on the
command line, and the task acts on exactly that record, not on "whatever the
current workspace happens to be."

### Rule of thumb

- **Request-context code** (controllers, helpers, views): always scope
  through the workspace association (`@workspace.projects.find_by!(...)`).
  Never a class-level finder on a `Tenanted` model — the code-smell spec
  enforces this.
- **Background code that deliberately spans workspaces** (jobs, rake tasks,
  console): query the model directly — either by iterating `Workspace.kept`
  and reading each workspace's own associations (Pattern 1), or by a
  business condition unrelated to tenant identity (Pattern 2). Never reach
  for `for_current_workspace` there; `Current.workspace` isn't set, and the
  scope will silently return nothing instead of everything.
- **Background code that means to act on one workspace** (the `DigestJob`
  example in step 6 above) sets `Current.workspace` explicitly and reads it
  back with `Current.workspace!` — the opposite of this section, and
  documented there.

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

The app includes a GDPR cookie consent banner via [biscuit-rails](https://github.com/garethfr/biscuit-rails), overridden at `app/views/biscuit/banner/_banner.html.erb` to fix three gaps in the gem's defaults (#500): **Reject non-essential** is the emphasized default action on first visit (not Accept — rejecting must be at least as easy as accepting), the banner is server-rendered `hidden` when consent already exists so it never flashes, and reopening the preferences panel (footer link) shows the visitor's actual saved choices instead of stale checkboxes. It renders at the bottom of every page and manages consent across 4 categories:

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

> **Keep Owner a permission superset.** A role can only be granted by someone who
> already holds every permission it confers (`ApplicationPolicy#may_grant?` — this
> is what blocks Admin→Owner escalation). So every permission you introduce —
> `manage_billing` above — must also be added to the **Owner** role, or *no one*,
> not even an Owner, can assign the role that uses it and it silently disappears
> from every role picker. Add the key to Owner in the same seed:
>
> ```ruby
> owner = Role.find_by!(slug: "owner", workspace_id: nil)
> owner.update!(permissions: owner.permissions.merge("manage_billing" => true))
> ```
>
> Editing `seeds.rb` does **not** touch Owner rows already persisted in
> production/staging — backfill those with a data migration.

## Next steps

- **[Architecture](/docs/developer/architecture)** — the request flow, tenancy model, and key directories your new code plugs into.
- **[Deployment](/docs/developer/deployment)** — ship it with Kamal once your feature is built.
- Browse the full **[docs index](/docs)** for feature-specific references (workspaces, notifications, identity, background jobs).
