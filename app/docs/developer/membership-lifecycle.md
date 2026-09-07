---
title: Membership Lifecycle
description: How a membership is granted, removed, and re-admitted — the kept/discarded state machine and the invariants that span User, Workspace, and Membership
keywords: membership lifecycle kept discarded reactivate readmit deactivate admit provenance granted_by self_join removed_by workspaces association replay idempotent archived
---

# Membership Lifecycle

A membership is a seat: granted, re-graded, revoked, restored. It is soft-deleted (`Discardable`), never destroyed while its workspace lives, and three rules about that state machine are spread across `User`, `Workspace`, and `Membership`. This page is their one home. Each rule is pinned by a spec named at the end.

## Two associations answer two different questions

`User has_many :memberships` is **unscoped**: it owns `dependent: :destroy` and it is what the members page reads, so removed people still show in history. `User has_many :workspaces` goes **through `active_memberships`, the kept ones only**. Every reader of `workspaces` — `WorkspaceScoped`'s resolver, the header switcher — is asking "which workspaces may this user enter". Routing it through every membership once let a removed member resolve the workspace, get refused by the policy, and be redirected back to the page that had just refused them (#931). Keep the two associations distinct; do not "simplify" `workspaces` onto `memberships`.

## Removal is idempotent by construction

`Membership#deactivate!` returns early when the row is already discarded. That is not defensive padding: `MembersController#destroy` resolves through the **unscoped** association on purpose (so the members page can show removed people), which means a replayed DELETE — a stale tab, the back button, a scripted retry — reaches the model with an already-removed membership. Without the guard, `discard!` re-stamped `discarded_at`, and the removal was notified and audited a second time.

The removal actor arrives as an argument (`deactivate!(removed_by:)`); the model never reads `Current` for it. Actor semantics for the notification fan-out are in [Notifications § The actor rule](/docs/developer/notifications).

## Re-admission is an UPDATE, and it is deliberately less guarded than admission

Two paths bring a removed member back: `Workspace#admit` finding a discarded row for the user, and `Membership#reactivate!` from the members page. Both are `undiscard!` — an UPDATE, not a create — so everything hung on creation (the `membership.created` audit row, the `after_create_commit` fan-out) never sees it. Two consequences are handled explicitly:

- **Notification.** `after_update_commit :notify_member_readmitted` fires on the kept transition so a returning member is welcomed and the owners told. It is registered under its own filter name because Active Record's `:commit` chain dedups callbacks by filter — reusing `:notify_member_added` would *replace* the create callback instead of adding to it.
- **Audit provenance.** `track_creation` is the only writer of `granted_by` onto the audit row, and it never runs here; `Membership#tracked_update_metadata` merges the granter into the `membership.updated` row on the reactivation path instead, so re-granting a previously removed member is not the one grant shape with no granter on record.

Re-admission is **not** gated on `Workspace#admittable?`, and that asymmetry with `Workspace#admit` is intentional. Outsider admission blocks archived, suspended, and deleted workspaces. Reactivation is only reachable through `WorkspaceScoped`, which already refuses deleted (`.kept`) and suspended (the redirect) workspaces, so only *archived* can reach it — and reactivating an existing member of an archived workspace is allowed: archive means "no new people, existing work continues", the member is not new, and the admin doing it is actively inside the workspace.

## Provenance is a model invariant, not only an entry-point guard

`granted_by` and `self_join` are mutually exclusive (a self-join has no granter — see the actor rule). `Membership.reject_conflicting_provenance!` raises `ArgumentError` at the two entry points, `Workspace#admit` and `#reactivate!`, before any database work, so the caller's own line is in the backtrace. But not every creation goes through an entry point: `User#join_shared_workspace` creates a membership directly, and the actor-stance code smell is satisfied by *either* marker, so a site naming both would look declared and reach the row. The `provenance_markers_are_coherent` validation is the second layer that catches every other path. Both layers are kept on purpose. The messages are programmer-facing; no form can produce them.

`self_join` has a closed grade set (`SELF_JOIN_GRADES`): a grade outside it is a typo, and the validation makes it fail loudly rather than read as a chosen self-join and mail somebody.

## Where these are pinned

- `spec/models/membership_spec.rb` — "deactivation" (replay idempotence), "reactivation of an archived workspace's member", "exclusive grant provenance … as a model invariant", "grant provenance on the audit row".
- `spec/code_smells/membership_creation_declares_actor_stance_spec.rb` — every creation site declares `granted_by:` or `self_join:`.
- `spec/models/user_spec.rb` — `workspaces` excludes discarded memberships.
