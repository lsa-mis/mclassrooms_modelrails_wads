---
title: Workspace-optional (none)
description: Stand up and verify the workspace-optional preset — signup creates no workspace; identity is at the User level; workspaces are created or joined explicitly
keywords: none preset workspace-optional user-first auth-first community event platform landing seam authenticated_home_path
---

[App Presets](/docs/developer/presets) › Workspace-optional

# Workspace-optional (`:none`)

**What it is.** Signup creates **no** workspace. A new user's identity lives at the User level; `Current.workspace` is legitimately `nil` until they explicitly create or join one. The workspace switcher, workspace-scoped nav, and workspace-scoped surfaces simply don't render for workspace-less users — the app is nil-safe throughout.

**Who it's for.** Auth-first / user-first products where workspaces are optional or emerge later: an event platform where users register and then join specific events, a community where members exist independently of any group, a personal dashboard that optionally connects to shared spaces. [Hallway Track](https://github.com/dschmura/hallwaytrack) is the reference downstream app using this posture.

## How users relate

Users exist at the platform level. A fresh signup has no workspace at all. Workspaces are created or joined through deliberate product flows — an event RSVP, a community invite, a "create your first team" prompt — rather than being implicit on arrival:

<svg viewBox="0 0 720 300" width="100%" role="img" aria-label="Workspace-optional: users exist at the platform level with no workspace created on signup. Alice signs in with a magic link and has no workspace yet. Bob signs in with Google OAuth, then explicitly creates a workspace. Carol signs in with email and password and joins a workspace via an invitation." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs>
    <marker id="arrow-none" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto">
      <path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/>
    </marker>
  </defs>

  <circle cx="42" cy="56" r="22" stroke-width="1.5"/>
  <text x="42" y="62" text-anchor="middle" fill="currentColor" stroke="none" font-size="16" font-weight="700">A</text>
  <text x="80" y="50" fill="currentColor" stroke="none" font-size="14.5" font-weight="600">Alice</text>
  <text x="80" y="70" fill="currentColor" stroke="none" font-size="11" opacity="0.7">signs in: magic link</text>

  <circle cx="42" cy="170" r="22" stroke-width="1.5"/>
  <text x="42" y="176" text-anchor="middle" fill="currentColor" stroke="none" font-size="16" font-weight="700">B</text>
  <text x="80" y="164" fill="currentColor" stroke="none" font-size="14.5" font-weight="600">Bob</text>
  <text x="80" y="184" fill="currentColor" stroke="none" font-size="11" opacity="0.7">signs in: Google OAuth</text>

  <circle cx="42" cy="260" r="22" stroke-width="1.5"/>
  <text x="42" y="266" text-anchor="middle" fill="currentColor" stroke="none" font-size="16" font-weight="700">C</text>
  <text x="80" y="254" fill="currentColor" stroke="none" font-size="14.5" font-weight="600">Carol</text>
  <text x="80" y="274" fill="currentColor" stroke="none" font-size="11" opacity="0.7">signs in: email + password</text>

  <rect x="450" y="28" width="240" height="56" rx="14" stroke-width="1.5" stroke-dasharray="6 4"/>
  <text x="570" y="52" text-anchor="middle" fill="currentColor" stroke="none" font-size="14.5" font-weight="600" opacity="0.45">no workspace yet</text>
  <text x="570" y="70" text-anchor="middle" fill="currentColor" stroke="none" font-size="11" opacity="0.35">created on explicit action</text>

  <rect class="text-accent" x="450" y="142" width="240" height="56" rx="14" stroke-width="2.25"/>
  <text x="570" y="166" text-anchor="middle" fill="currentColor" stroke="none" font-size="14.5" font-weight="700">Bob's Event</text>
  <text x="570" y="184" text-anchor="middle" fill="currentColor" stroke="none" font-size="11" opacity="0.7">created explicitly</text>

  <rect class="text-accent" x="450" y="230" width="240" height="56" rx="14" stroke-width="2.25"/>
  <text x="570" y="254" text-anchor="middle" fill="currentColor" stroke="none" font-size="14.5" font-weight="700">Acme Community</text>
  <text x="570" y="272" text-anchor="middle" fill="currentColor" stroke="none" font-size="11" opacity="0.7">joined via invitation</text>

  <path d="M280 54 Q 365 54 446 56" stroke-width="1.5" stroke-dasharray="6 4" marker-end="url(#arrow-none)"/>
  <text x="362" y="42" text-anchor="middle" fill="currentColor" stroke="none" font-size="11" opacity="0.5">no workspace on signup</text>

  <path class="text-accent" d="M280 168 Q 365 170 446 170" stroke-width="2.25" marker-end="url(#arrow-none)"/>
  <text x="362" y="156" text-anchor="middle" fill="currentColor" stroke="none" font-size="11">Owner · created it</text>

  <path class="text-accent" d="M280 258 Q 365 260 446 258" stroke-width="2.25" marker-end="url(#arrow-none)"/>
  <text x="362" y="246" text-anchor="middle" fill="currentColor" stroke="none" font-size="11">Member · via invitation</text>

  <text x="360" y="296" text-anchor="middle" fill="currentColor" stroke="none" font-size="11" opacity="0.7">No workspace is created on signup · workspaces appear only through explicit product flows</text>
</svg>

**What you get when configured.**

| Knob | Value | Mechanism |
|---|---|---|
| `signup.mode` | `:open` or `:invite_only` — your call | `config/initializers/signup.rb` (`SIGNUP_MODE`) |
| `tenancy.onboarding` | `:none` — no workspace created at all | `WORKSPACE_ON_SIGNUP=none`; the `User#onboard_workspace` callback is a no-op |
| `tenancy.workspace_creation` | `:enabled` — users can create workspaces when your product flow calls for it | `WorkspacesController#new` |
| `permitted_join_strategies` | `[:invite]` default; add `open_link` for link-join | `SIGNUP_PERMITTED_JOIN_STRATEGIES` |

## First-run onboarding wizard

New users under `:none` are funneled through a mandatory first-run onboarding wizard before they reach their home. The wizard is driven by the `RequiresOnboarding` concern (included in `ApplicationController`) and the `OnboardingsController` step dispatcher.

**Guard.** `RequiresOnboarding#require_onboarding` fires as a `before_action` on every authenticated HTML request. It redirects to `onboarding_path` when all three conditions hold:

- `TenancyConfig.none?` — the guard is completely inert in `:personal`, `:shared`, and `:single_tenant` postures.
- `Current.user.onboarded?` is false — `users.onboarded_at` is nil.
- `request.format.html?` — background XHR/JSON requests (e.g. the timezone beacon) pass through.

Controllers that must be reachable mid-wizard (the wizard steps themselves, sign-out, `EmailVerificationsController`) call `skip_onboarding_requirement` to opt out.

**Step dispatcher.** `OnboardingsController#show` reads `User#onboarding_step` (derived from the user's data, not a persisted column) and redirects to the appropriate step:

| `onboarding_step` | Redirects to |
|---|---|
| `:workspace` | `new_onboarding_workspace_path` — name the workspace |

**Wizard steps** (all under `Onboarding::BaseController`):

1. **`Onboarding::WorkspacesController`** — user names their workspace; on save, `onboarded_at` is stamped immediately and the user lands on the workspace.

The wizard is a single step in the base template — the example domain that used to add project/tools/team steps here has been removed. A fork that needs a multi-step wizard adds its own steps around its own domain models, following the same `Onboarding::BaseController` pattern.

**Skipping/finishing.** `PATCH /onboarding` hits `OnboardingsController#update`, which sets `onboarded_at` immediately and redirects to the workspace (or `root_path` if none exists yet). Once `onboarded?` is true the guard never fires again.

See [Onboarding](/docs/user/onboarding) for a full walkthrough, screenshots, and i18n keys.

## Setup

**1. Set the onboarding knob.**

```
WORKSPACE_ON_SIGNUP=none
```

That's the only required change. No seed vars are needed (unlike `:shared`).

**2. Override `authenticated_home_path` (optional).**

Every post-auth landing — `SessionsController`, magic-link, OAuth, and `redirect_if_authenticated` — routes through `authenticated_home_path`. For already-onboarded users this is where they land. The default is `root_path`. Override in your fork if your workspace-agnostic home lives elsewhere:

```ruby
# app/controllers/application_controller.rb  (or a concern)
private

def authenticated_home_path
  dashboard_path   # or workspaces_path, root_path, wherever your workspace-agnostic home lives
end
```

For most `:none` apps you'll point it at a dedicated user home — a profile page, a dashboard, an event listing — that makes sense whether or not the user has any workspaces. New users won't reach this until they've completed (or skipped) the onboarding wizard.

**3. Build a workspace-agnostic home view.**

Your home view should work when `Current.workspace` is `nil`. The workspace switcher, workspace-scoped sidebar items, and workspace-scoped nav links already guard on `Current.workspace.present?` and are simply absent for workspace-less users — you don't need to add nil checks on your own.

## Zero-workspace safety

The app is nil-safe throughout. When `Current.workspace` is `nil`:

- The **workspace switcher** does not render.
- **Workspace-scoped** sidebar sections and nav links are hidden.
- **`Tenanted` model scopes** are never reached from workspace-less contexts — your user-scoped controllers don't set `Current.workspace`, so workspace-scoped queries never run.

You are responsible for nil-guarding any custom views or partials you add that reference `Current.workspace` directly. The template's own surfaces are safe.

## Verification

After `bin/setup`, open a console:

```bash
bin/rails console
```

```ruby
user = User.create!(
  email_address: "test@example.com",
  first_name: "Test", last_name: "User",
  password: "SecureP@ssw0rd123!", password_confirmation: "SecureP@ssw0rd123!"
)

user.workspaces.count   # => 0
```

A count of zero confirms the preset: no workspace was auto-created.

Browser verification (requires `SIGNUP_MODE=open` or a valid invitation) — sign up a fresh user and confirm:

1. After submitting the registration form, you are redirected to the "check your email" screen (`EmailVerificationsController#new`).
2. A non-blocking "confirm your email" banner renders in the authenticated layout until the verification link is clicked.
3. After clicking the verification link, the onboarding wizard starts — you are redirected to `onboarding_path` and land on the workspace-naming step.
4. Completing or skipping the wizard stamps `onboarded_at` and lands on the workspace.
5. The workspace switcher is absent until a workspace exists.
6. No workspace appears in `user.workspaces` until they explicitly create or join one.

**When to switch presets.**

- *"Every user should get their own private workspace automatically."* → **[Solo-default](/docs/developer/presets-solo)** — the shipped default.
- *"Everyone lands in one shared workspace."* → **[Single-tenant](/docs/developer/presets-single-tenant)** (Reshape 1).
- *"Users get a personal workspace and can also join or create org workspaces."* → **[Open SaaS](/docs/developer/presets-open-saas)** (Reshape 2+).

> **Switching TO `:none` on a live app** is effectively a from-scratch product shape, not a config flip. Existing users who already have workspaces keep them; the `WORKSPACE_ON_SIGNUP=none` change only affects new signups. A live migration would require a separate cleanup pass and a redesigned home experience — plan this at setup time.

## Next steps

- **[← Compare all presets](/docs/developer/presets)** — the decision matrix and the other three shapes.
- **[Forking →](/docs/developer/forking)** — override `authenticated_home_path` and other fork seams for your product.
- **[Extending ModelRails →](/docs/developer/extending)** — add your own user-scoped features on top of this preset.
