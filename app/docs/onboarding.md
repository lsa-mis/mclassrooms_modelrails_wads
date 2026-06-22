---
title: Onboarding Journey
description: How first-run onboarding works under the none posture — step flow, state model, email-verification gate, and fork seams.
keywords: onboarding first-run wizard workspace project team invite none posture WORKSPACE_ON_SIGNUP onboarded_at email verification
audience: [guide, technical]
---

# Onboarding Journey

The onboarding wizard is active only when `WORKSPACE_ON_SIGNUP=none`. In every other posture (`personal`, `shared`) the wizard is inert — all guard logic returns early before any redirect fires. See [/docs/presets-none](/docs/presets-none) for the broader none-posture setup.

> See this journey drawn as a wireframe in [Application Flows](/docs/application-flows).

## When it triggers

`RequiresOnboarding` (`app/controllers/concerns/requires_onboarding.rb`) installs a `before_action` in `ApplicationController`. The guard redirects to `onboarding_path` only when **all three** conditions hold:

1. `TenancyConfig.none?` — the app is running under `WORKSPACE_ON_SIGNUP=none`.
2. `Current.user && !Current.user.onboarded?` — a signed-in user who has not yet completed setup.
3. `request.format.html?` — a page navigation, not a background XHR or JSON request.

Controllers that must stay reachable mid-wizard (the wizard itself, sign-out, email verification/resend) call `skip_onboarding_requirement`.

## State model

Only one column is persisted: `users.onboarded_at`. Everything else is derived on demand.

- `User#onboarded?` — `onboarded_at.present?`
- `User#onboarding_workspace` — `workspaces.kept.first` (the first kept workspace owned by the user)
- `User#onboarding_step` — derived from the workspace + project state:

```ruby
def onboarding_step
  workspace = onboarding_workspace
  if workspace.nil?
    :workspace
  elsif workspace.projects.kept.none?
    :project
  else
    :team
  end
end
```

`onboarded_at` is stamped by whichever action completes setup — `OnboardingsController#update` (skip/finish), `Onboarding::TeamsController#create` (send invites), or `Invitation#accept_client_invitation!` (client invite acceptance).

## Step flow

`OnboardingsController#show` is the single entry point. It reads `User#onboarding_step` and dispatches:

| Step | Controller | What happens |
|------|-----------|--------------|
| `:workspace` | `Onboarding::WorkspacesController` (`new`/`create`) | Name the workspace |
| `:project` | `Onboarding::ProjectsController` (`new`/`create`) | Name the first project |
| *(tools interstitial)* | `Onboarding::ToolsController` (`new`/`create`) | Choose enabled tools — only reached from `ProjectsController#create` when `ProjectTools::Registry.toggleable.size > 1`; the resume dispatcher (`OnboardingsController#show`) never routes here |
| `:team` | `Onboarding::TeamsController` (`new`/`create`) | Invite teammates or skip |

`OnboardingsController#update` (PATCH `/onboarding`) provides a "skip for now" / finish path at any point after workspace creation.

### Base controller

All step controllers inherit from `Onboarding::BaseController`, which:

- Calls `skip_onboarding_requirement` (so the wizard is not caught by its own guard).
- Uses `layout "onboarding"`.
- Runs `require_not_onboarded` — redirects already-finished users to `root_path`.
- Runs `set_onboarding_workspace` — resolves `Current.workspace` from `User#onboarding_workspace`; `nil` at the workspace step.

`Onboarding::BaseController` does **not** include `WorkspaceScoped` — workspace context is set manually via `set_onboarding_workspace`.

## Routes

```ruby
resource :onboarding, only: %i[show update]

namespace :onboarding do
  resource :workspace, only: %i[new create]
  resource :project,   only: %i[new create]
  resource :tools,     only: %i[new create]
  resource :team,      only: %i[new create]
end
```

## Soft email-verification gate

Email verification runs in parallel with onboarding — it is non-blocking.

- Magic-link signup (`MagicLinkCallbacksController#create`) marks the email as verified immediately (the link itself proves ownership). The email-verification gate is only relevant for users who registered via a legacy path and have an unverified email. `EmailVerificationsController#new` renders a Resend button (`email_verification_resend` route).
- A reminder banner (`app/views/shared/_email_verification_banner.html.erb`) appears in the authenticated layout whenever `Current.user.email_verification_pending?` is true.
- `EmailVerificationsController#show` (token link) verifies the address and lands on `authenticated_home_path`.

The wizard proceeds regardless of verification status — users can complete all onboarding steps before verifying their email.

## Fork seams

To customize onboarding in a fork:

- **Different steps** — add step controllers inheriting from `Onboarding::BaseController`; add routes under `namespace :onboarding`.
- **Different state** — override `User#onboarding_step` to return your custom symbols; add a corresponding `when` branch in `OnboardingsController#show`.
- **Skip onboarding entirely** — override `User#onboarded?` to always return `true`, or remove the `RequiresOnboarding` include from `ApplicationController`.
- **Different landing** — override `authenticated_home_path` in `Authenticatable` (see [/docs/presets-none](/docs/presets-none)).

See [/docs/project-tools](/docs/project-tools) for how the tools interstitial fits into the step flow.
