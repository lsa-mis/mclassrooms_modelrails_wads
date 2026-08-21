---
title: Architecture
description: Data model, authorization, and real-time patterns in ModelRails
keywords: models workspace membership pundit authorization turbo streams multi-tenancy tenanted sqlite wal single-writer concurrency race capacity owner invariant sweep retention activity log audit postgres
---

# Architecture

## Data Model Hierarchy

```
User
  └── Workspace (personal, auto-created on sign-up)
  └── Workspace (organizational, created manually)
        ├── Membership (user + Role with permissions JSON)
        └── Invitation (polymorphic — currently workspace only)
```

The template ships this workspace/membership/role/invitation core deliberately
thin — the example domain that previously hung off `Workspace` (a demo
collaboration model and its nested records) has been removed so a fork's own
domain models can take its place. The `Tenanted` concern (see below) and the
`draw(:app)` routing seam exist specifically so a fork's tenant-scoped models
drop in without touching template code.

## Key Concepts

**Workspace** — organizational boundary. Billing, roles, member management. Every user has a personal workspace created on sign-up.

**Role** — workspace-level roles with permissions JSON. Four system defaults: Owner, Admin, Member, Viewer. Forkers add custom roles via seeds.

**Tenanted** (`app/models/concerns/tenanted.rb`) — the fork's extension seam for tenant-scoped domain models: `include Tenanted` on a model with `belongs_to :workspace` to get a `.for_current_workspace` scope keyed off `Current.workspace`. See the "Deliberate architectural deviations" section of `CLAUDE.md` for the tradeoff this concern accepts.

## Authorization

Pundit policies check permissions at the workspace level: `ApplicationPolicy#can?("permission_name")` reads from `role.permissions` JSON. A fork's own tenant-scoped models add their own policies alongside this pattern.

Authorization is opt-in per action (there is no global `verify_authorized`), but it's **enforced at CI**: `spec/code_smells/mutating_actions_are_authorized_spec.rb` walks every mutating (POST/PATCH/PUT/DELETE) route and fails the suite if the action neither calls `authorize` nor is on a reviewed allow-list. The allow-list holds only actions that are public auth-entry flows or act solely on the current user's own resources. So a new mutating controller that forgets `authorize` on a tenant resource fails a test rather than shipping a silent IDOR — add the `authorize` call, or add the action to the allow-list with a one-line rationale if it's genuinely public/self-scoped. Pairs with the tenant-load guard (`no_unscoped_tenant_loads_spec`): that one stops loading the wrong record, this one stops the missing check.

**Granting roles** is gated separately by `ApplicationPolicy#may_grant?(role)`: an actor can grant a role only if they already hold every permission it confers (a superset check, not a rank). This blocks privilege escalation — e.g. an Admin promoting anyone to Owner — and `MembershipPolicy#update?`/`#reactivate?` additionally refuse to manage a membership whose role the actor couldn't grant. `Workspace#admit` (invitation-accept / open-link self-join) deliberately does **not** re-check this: the role is authorized when the invitation or link is *created* (`authorize_role_grant!`), not when redeemed. If you add a new membership-grant entry point, gate the role where it is minted, not where it is consumed.

## Concurrency: SQLite's Single Writer as a Race-Safety Net

The template runs on single-host SQLite in WAL mode. WAL admits many concurrent readers but still exactly **one writer at a time** — every write transaction is serialized by a database-level writer lock. Two consequences shape how multi-row invariants are enforced:

- **Lock-then-guard is atomic.** Rails 8.1's SQLite adapter opens write transactions with `BEGIN IMMEDIATE`, taking the writer lock *before* the first read. So a `transaction { lock!; guard; mutate }` block is genuine check-then-act, not a TOCTOU window. (One adapter quirk: `lock!` raises on records with unsaved changes, so these guarded mutators require clean records.)
- **Row-level `lock!` is not a cross-connection lock.** SQLite locks are per-connection, so `workspace.lock!` in a pre-flight validation is silently a no-op against a racing connection. Pre-flight checks therefore exist for their *user-facing error message*, not for safety. The safety comes from re-checking the invariant **after** the write, inside the same transaction: by that point the database's writer lock has already serialized the transaction against any racer, so a `COUNT`/`EXISTS` there reflects committed state — including a racer that slipped in first. If the invariant is broken, the check raises and the whole transaction rolls back.

Three kinds of sites lean on this property:

- **Capacity checks** — `Membership`'s pre-flight validator produces the friendly error; an `after_create` invariant check inside the create transaction is the net that actually prevents over-capacity under concurrency.
- **Last-owner / owner-floor checks** — deactivating, demoting, or transferring away a workspace's owner re-counts remaining kept owners *after* the mutation and rolls back if none remain. Ownership transfer additionally uses an atomic conditional `UPDATE` (demote only if still owner; zero affected rows → abort before promoting the target), so a racing transfer can never leave a workspace with two owners.
- **Sweep jobs** — `ExpiredSessionsSweepJob`, `WebauthnChallengesSweepJob`, `NotificationCleanupJob`, and `ActivityLogRetentionSweepJob` all `delete_all` in batches of ~100. A large one-shot delete would hold the single writer lock for seconds and block interactive writes (sign-ins, incoming notifications); per-batch transactions release the lock between rounds, capping any single stall. The swept tables have no destroy callbacks or `dependent:` cascades, so `delete_all` is behavior-identical to `destroy_all` and instantiates nothing.

**A fork moving to Postgres must revisit all of this.** The assumptions invert: `SELECT … FOR UPDATE` (`lock!`) becomes a real cross-connection lock — so the pre-flight lock-then-check patterns become load-bearing — while the after-write re-checks *lose* their guarantee, because under `READ COMMITTED` concurrent transactions don't see each other's uncommitted rows and two racers can both pass an in-transaction `COUNT`. Carry each invariant with an explicit mechanism instead: row locks on the parent workspace, database constraints, or advisory locks. The batched sweeps remain harmless on Postgres, just no longer necessary for writer-lock latency.

## Activity Tracking

The `Trackable` concern auto-creates `ActivityLog` records via `after_commit` callbacks. Models opt in with `include Trackable`. Sensitive attributes (tokens, passwords) are stripped from metadata.

**The trail is best-effort by design.** Activity writes rescue and log rather than ever failing the business operation they describe, so the log is an operational/product feature — not compliance-grade evidence. Rows are read-only once persisted (#604), and relation-level writes are fenced by `spec/code_smells/activity_log_immutability_spec.rb`.

**Retention is bounded at 12 months** by `ActivityLogRetentionSweepJob` (#438). Bounded retention is the honest guarantee: keeping a best-effort trail forever would make the system's behavior contradict its own contract — exactly what a fork owner would misread as compliance evidence. An unbounded high-write table on single-host SQLite is also a backup/`VACUUM` problem discovered at the worst possible time. The sweep is the one documented door through the immutability guarantee — it is registered, with its reason, in the immutability spec's `allowed_bypasses`. A regulated fork that needs longer retention changes one line (`RETENTION_WINDOW`); a fork promoting the trail to compliance-grade must also move the activity write *inside* the business transaction so it can no longer be silently dropped.

## Owner Lookup

`Workspace#owner` returns a single owning user and deliberately uses `detect` over `memberships` (not `joins` + `find_by`) so it works from preloaded associations without a per-row query in list views.

`Workspace#owners` returns **all** users currently holding a kept owner-role membership — used by the capacity-approaching sweep to alert every owner, and by any ownership-management UI that needs the full roster. It **always issues a fresh query**, even when `memberships` is preloaded: its callers are notifier recipient resolution paths that run right after mutations changing the owner roster, so a cached array can't be trusted.

Render paths that only need a last-owner *existence check* (the Leave button — `MembershipPolicy#destroy?`) use `Membership.other_kept_owners(...).exists?` instead: one indexed EXISTS, fired only for owner rows, rather than materializing the roster per render.

## Real-Time

Turbo Stream broadcasts via `broadcast_refresh_to` (Turbo 8 morph-based refresh). Workspace stream for membership/invitation/settings changes.

## Markdowndocs Gem Integration

The `markdowndocs` gem renders this site's `/docs` content. Two host-side adaptations layer on top of the gem's defaults so it fits this app's design system and CSP:

**View overrides** (`app/views/markdowndocs/docs/`) — six ERB files (`show`, `index`, `_card`, `_breadcrumb`, `_navigation`, `_mode_switcher`) that mirror the gem's templates but route every color through this app's semantic tokens (`bg-surface-raised`, `text-text-heading`, `text-accent`, etc.) instead of the gem's hardcoded Tailwind palette pairs. The token system flips coherently with `class="dark"` on `<html>`. Rails view resolution prefers `app/views/` over engine view paths, so these overrides take precedence at render time.

**Mobile sidebar Stimulus controller** (`app/javascript/controllers/docs_sidebar_controller.js`) — replaces the gem's inline `onclick` handler for the mobile hamburger toggle. The host's CSP locks `script-src` to `:self` with nonces and disallows `unsafe-inline`, so the host override of `show.html.erb` wires the toggle via Stimulus actions instead.

Both layers can be removed if the gem itself starts shipping token-friendly templates and CSP-clean Stimulus interactivity. Until then, see [troubleshooting.md](/docs/developer/troubleshooting) if a class fails to compile or a controller fails to register.
