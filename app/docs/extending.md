---
title: Extending
description: How to add resource types, custom roles, and new features to ModelRails
keywords: resource types roles permissions migration polymorphic customization logo branding cookies gdpr consent analytics
audience: [guide, technical]
---

# Extending ModelRails

## Adding a New Resource Type

The Resource registry uses a polymorphic pattern. To add a new type (e.g., `Slideshow`):

### 1. Create the model

```bash
rails generate model Slideshow
```

```ruby
# app/models/slideshow.rb
class Slideshow < ApplicationRecord
  has_one :resource, as: :resourceable, dependent: :destroy
  has_many :slides, dependent: :destroy
end
```

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
