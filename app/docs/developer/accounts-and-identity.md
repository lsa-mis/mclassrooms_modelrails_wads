---
title: Accounts and Identity
description: The three-tier identity and tenancy model — User, your workspace, and organization workspace — and the canonical vocabulary every fork inherits
keywords: identity user workspace tenant membership role current-workspace personal organization account tiers switcher WORKSPACE_ON_SIGNUP
---

# Accounts and Identity

This page names the three-tier identity and account model **that already exists** in this template. Its correctness was built in; this document makes it visible to forks.

> **Model vs. surfaces.** The *model* below — `User`, `Workspace`, `Membership` — is built and verified. Two *surfaces* named here are the **target shape**, being adopted incrementally: the `/me` + `/settings` split (the template reaches identity settings under `/account/*` today) and the context switcher. The vocabulary is canonical now; those routes land in a later phase.

## The three tiers

The model separates identity (who you are) from tenancy (where your data lives). There are three legible tiers:

| Tier | Entity | Where you reach it | What it holds |
|---|---|---|---|
| **Identity** (the human) | `User` | `/me` (home) + `/settings` | login, avatar, preferences, linked logins — *account-independent* |
| **Your workspace** (your own tenant) | `Workspace` (auto-created, growable) | the context switcher; default landing in solo apps | your individual scoped data; can grow into a team |
| **Organization workspace** (shared tenant) | `Workspace` | the context switcher | a team's scoped data, many members + roles |

A **context switcher** sets `Current.workspace`. Identity (`/me`, `/settings`) is reachable from any context and belongs to none of them.

## Identity vs. tenancy

Identity is **user-scoped and account-independent.** A `User` record holds login credentials, avatar, preferences, and linked OAuth logins. None of that is workspace-specific — it travels with the person, not the context.

Tenant data is **workspace-scoped.** Business objects, records, and collaboration all live inside a `Workspace`. The `Tenanted` concern and `Current.workspace` enforce that boundary at the query and access level. Switching workspace context changes which data you see; your identity settings remain constant.

## One Workspace, two flavors

There is a single `Workspace` model for both your own workspace and an organization workspace. They differ only in how they were created and how many members they have — not in their data structure.

When a new user signs up, an auto-created workspace is flagged `owner_created: true` (and `personal: true` in the current column). That flag marks the starting point — it does not cap membership. "Your workspace" can grow into a team. "Graduation" to an organization is a transfer or scale path, not a new model entity.

`Membership` joins `User` to `Workspace` with a `Role`. Every user is a member of every workspace they can access, including their own.

## Canonical vocabulary

These are the correct terms. Use them in UI copy, docs, and code comments. "Account" is an overloaded word that means the human in one context and the tenant in another — retire it for tenant concepts.

| Concept | Canonical term | Avoid |
|---|---|---|
| The human / login | **User** | "account" (as a tenant) |
| The tenant container | **workspace** | "account", "org", "team" (as the model entity) |
| Your auto-created workspace | **your workspace** | "personal workspace" (it can grow — "personal" lies) |
| A multi-member tenant | **organization workspace** | "team", "company" (pick one later; don't bake it into model names) |
| The active-context selector | **context switcher** | "workspace selector", "account switcher" |
| Settings about you | **identity settings** (at `/settings`) | "account settings" (when meaning the person) |
| Settings about a workspace | **workspace settings** (reached via the switcher) | "account settings" (when meaning the tenant) |

## Password lifecycle

A password is optional (`has_secure_password validations: false`); the passwordless flows are primary. When one exists, three rules govern its removal and its checks, all on `User`.

**`remove_password!` tears down password authentication as one unit** — the email authentications, the digest, and whatever the caller needs committed alongside (session revocation, via the block) — and returns whether *this* caller performed the removal. Two details are load-bearing:

- The `reload` at the top of the transaction is the concurrency guard (#826). A second request that loaded the user before the first removal committed still holds the old digest in memory; its `update!` would issue a real UPDATE, satisfy `saved_change_to_password_digest?`, and write a second `user.password_removed` audit row. Re-reading inside the transaction — where the write lock is already held, so the read is current — makes the second caller a no-op instead.
- It uses `save!(validate: false)`, not `update_columns` and not `update!`. `update_columns` silently skips callbacks, and the strict audit row and the post-commit notifier are the point of taking the callback path (#813). `validate: false` drops full-record validation so a record that drifted invalid for reasons unrelated to credentials — an attachment allowlist tightening, say — cannot hold the removal hostage (#820).

**Every digest-touching path notifies** (settings change, reset, removal): the notifier hangs on the model, not the controllers, so no path can forget. The audit row is strict-tier and the notice is post-commit; see [Architecture § Activity Tracking](/docs/developer/architecture) for why those two sit on different callbacks.

**Lockout** is `MAX_FAILED_ATTEMPTS` (5) failed logins, held for `LOCK_DURATION` (1 hour); `register_failed_login!` and `register_successful_login!` are the only writers of the counter.

**The Have I Been Pwned check runs before `save`**, outside the write transaction — see [Architecture § Concurrency](/docs/developer/architecture) for the timing and [Security § Password Security](/docs/developer/security) for its fail-open posture.

## For forks

See [Forking this template](/docs/developer/forking) for the full forking guide and the four signup presets.

`WORKSPACE_ON_SIGNUP` controls which workspace, if any, a new user lands in at registration:

- `personal` — auto-create and land in "your workspace" (the default solo posture)
- `shared` — land every new user in a single shared workspace (single-tenant SaaS)
- `none` — no workspace at signup; the user is redirected to create or join one

This env var pairs with `SIGNUP_MODE` (open/invite-only/closed) to define the full onboarding posture. The model above is the same in all three cases — only the initial landing changes.
