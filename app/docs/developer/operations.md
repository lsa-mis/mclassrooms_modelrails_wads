---
title: Instance operations
description: Who an operator is, how the first one comes to exist, what the operations area can and cannot do, and the security posture around it
keywords: operator operations admin instance bootstrap invite-only suspend lock workspace activity owner
---

# Instance operations

An **operator** administers the whole instance from above the workspaces:
creating and locking workspaces, looking users up, granting other operators,
and reading activity across every workspace. Operators are ordinary users
with an `Operatorship` row — nothing else marks them out, and holding one
does not make them a member of anything. The operations area never opens a
workspace the way a member does; see [Extending: Cross-workspace
queries](extending#cross-workspace-queries), Pattern 4.

## Day one on an invite-only instance

Nobody can reach `/operations` until an operator exists, and both
`operators:grant` and `tenancy:owner_setup_link` abort with "User not found"
if the email has no account yet — so a person must exist first.

Under the `:shared` preset (see [App Presets](presets)) the grant already
happened: the seed gives the bootstrap Owner an operatorship at boot, because
on that preset someone has to be able to create workspaces and see users
before anyone else exists. The seed also gives that account a placeholder
password nobody knows, so you still claim it with the
`tenancy:owner_setup_link` line below — skip only `operators:grant`.

On any other preset, `db:seed` creates no user, so pick the path that matches
your `SIGNUP_MODE`:

- **Signup is open.** Register through the normal flow first
  (`/session/new` → registration magic link → name), then continue below.
- **Signup is invite-only.** Nobody can register yet, so mint the
  account from the console — `User.create!` needs only `email_address`,
  `first_name` and `last_name`; a password is optional. This also runs
  `User#onboard_workspace` like any other signup, so depending on your
  `WORKSPACE_ON_SIGNUP` preset it may hand the new account a personal
  workspace or a shared-workspace membership as a side effect — harmless for
  an operator account, but worth knowing before you're surprised by it in
  the member list.

  ```sh
  bin/rails runner 'User.create!(email_address: "me@example.com", first_name: "Me", last_name: "Operator")'
  ```

Either way, then:

```sh
bin/rails 'operators:grant[me@example.com]'
bin/rails 'tenancy:owner_setup_link[me@example.com]'
```

The quotes matter in zsh, the shell a Mac opens by default: unquoted square
brackets are a glob pattern, and the command stops at "no matches found"
before Rails sees it.

`operators:grant` grants an `Operatorship` (idempotent — running it again
just reports they're already an operator) and records the address as
verified — an operator typed it, the same vouching the `:shared` seed does —
which is what sending invitations requires (`User#can_invite?`); a
console-minted account has no verified address otherwise, and its first
create-for-owner would be refused with "Verify your email address before
sending invitations." When both commands finish the account can sign in,
operate, and invite. `tenancy:owner_setup_link` mints
a short-lived `set_password`-intent sign-in link and **prints it to your
terminal** — it is never emailed, so this step needs no working SMTP even on
an invite-only instance where the open-signup path above does. Opening the
link and confirming signs you in (satisfying the reauthentication the area
force-checks on every request, [below](#how-it-stays-safe)) and lands you on
`/settings/password/new` to set one; open `/operations` from there, or
navigate there directly while that sign-in is still fresh. If you let the 15-minute
reauth window lapse before setting a password, the next `/operations`
request bounces you to the reauthentication interstitial, and a
still-passwordless account's only factor there is an emailed one-time code —
so set a password in that first window if outbound mail isn't wired up yet.

## What the area does

- **Workspaces** (`/operations/workspaces`) — every kept workspace, locked
  ones included. Open one to see its member list and recent activity, lock
  or unlock it, or create a new one: an existing user's email makes them the
  owner immediately; an unknown email makes *the operator* the interim
  owner and sends that email an ordinary workspace invitation carrying the
  Owner role. See [The operator becomes the owner](#the-operator-becomes-the-owner)
  below — this is deliberate. Creation honors `TENANCY_WORKSPACE_CREATION`
  the same as the tenant-side flow; the operations area does not bypass it.
- **Users** (`/operations/users`) — a search box, not a browsable list: look
  a user up by their exact email address (names are encrypted
  non-deterministically and can't be searched or sorted in SQL — see
  [Security: Personal Data at Rest](security#personal-data-at-rest)). From a
  user's page, let a locked-out account try again, or suspend or reinstate
  them (sign-in is refused and sessions end; memberships and roles are
  untouched). An operator can't be suspended from here — revoke their
  operator access first; `rails users:suspend` is the unguarded break-glass
  path. See [Suspension keeps memberships](#suspension-keeps-memberships)
  below.
- **Activity** (`/operations/activity_logs`) — every workspace's activity,
  newest first, paginated. Personal security events (password changes,
  passkeys, new devices) never appear here — that split is the same `admin`
  vs. `personal` visibility the rest of the app already uses.

  One kind of `admin` row is excluded on top of that split: a suppressed
  invitation delivery. Those rows are the only evidence that a recipient
  blocked an inviter, and on a single-operator instance the operator is
  usually the inviter — so admin visibility alone would hand them a way to
  confirm a block. `ActivityLog::INVITER_UNREADABLE_ACTIONS` names them and
  the feed filters them out. If you add an action whose existence would tell
  an inviter something a recipient chose not to tell them, add it there too.
- **Operators** (`/operations/operatorships`) — who can do all this, and who
  granted them. Granting takes an email that must already belong to a user;
  revoking removes an `Operatorship`, except the last one — see [How it
  stays safe](#how-it-stays-safe).

## What it deliberately does not do

- Act *inside* a workspace. Editing projects, changing settings, inviting
  members — that's a member's job. Grant yourself a membership the ordinary
  way if you need to do it (or, for a workspace you just created for an
  unknown owner, you're already in it).
- Scope an operator to some workspaces rather than all of them. An
  operator's reach is the whole instance today — `operated_workspaces` is
  every kept workspace, with no notion of "some." A scoped-operator arc that
  narrows this is planned, not built.
- Impersonate a user.

## The operator becomes the owner

Creating a workspace for an email with no account doesn't leave that
invitation floating with nobody to receive it: the operator who created the
workspace becomes its owner immediately, and the invited email gets an
ordinary Owner invitation through the same path any workspace invitation
uses. This was deliberate, not an oversight — "invited to nothing" isn't a
state this product has a page for, and routing it through the ordinary
invitation flow means every other page in the app can keep assuming a
workspace always has an owner.

The consequence: until the invited owner accepts, the operator is a real,
tenant-visible member of that workspace, showing up in its member list like
anyone else. Nothing removes them automatically — not on acceptance, not
ever. Hand off deliberately, the same way any owner would: transfer
ownership or leave the workspace once the new owner is in place. An operator
who creates workspaces regularly and never hands off accumulates
memberships this way; tracked as #1118.

## Suspension keeps memberships

Suspending a user discards nothing: memberships, roles and project access
are all left exactly as they were. A suspended sole owner still owns their
workspace, and reinstating them restores that access with no further
repair. While they're suspended, that workspace simply has no active
owner able to sign in — that's the point of a hold, not a gap in it.

## How it stays safe

- A non-operator gets a 404 on every `/operations` route — the area's
  existence isn't confirmed to them.
- Every request re-checks reauthentication, hard-wired on
  (`force: true`): it fires even for a fork that has turned
  `reauth_enabled` off. This is the app's only surface gated on *every*
  action, GET included, not just mutations — see [Security:
  Re-Authentication](security#re-authentication-sensitive-changes).
- `Operations::` controllers never include `WorkspaceScoped` and never set
  `Current.workspace`; a workspace is reached only through the signed-in
  operator's own reach relation, `Current.user.operated_workspaces`. See
  [Extending: Cross-workspace queries](extending#cross-workspace-queries),
  Pattern 4.
- The last operator can't be revoked from the panel — the roster refuses, so
  an instance can't lock everyone out through the UI. See [Locked out
  (break-glass)](#locked-out-break-glass) below for the server-access path.

  The guard (`Operatorship#revoke_by_operator!`) is atomic under
  concurrency: `BEGIN IMMEDIATE` opens the transaction at the block's first
  statement, so the count runs under the writer lock (`lock!` is only a
  reload on SQLite, not the mechanism) — two operators revoking two
  *different* rows can't both pass the count check and leave zero (the
  lock-then-check shape of every guarded mutator — see [Architecture §
  Concurrency](architecture); a Postgres fork must add an explicit lock). It
  also refuses an operator revoking their own row outright, and checks that
  case AFTER the last-operator one:
  when only one operator remains, that operator is necessarily the one
  attempting the revoke, so `:last_operator` is the more useful refusal — it
  names the break-glass path, where a generic self-revoke refusal would
  point at a second operator who doesn't exist.
- Granting and revoking an operatorship writes an audit row in the same
  transaction as the grant or revoke, and those rows sit behind the
  security retention floor described in [Security: Activity
  Tracking](security#activity-tracking).
- An operator locking or unlocking a workspace shows up in that workspace's
  *own* activity feed too, named as the actor — a tenant owner can see that
  an operator touched their workspace, not just that it happened.

## Locked out (break-glass)

Three rake tasks are the server-access door the panel deliberately can't
open:

```sh
bin/rails operators:list             # who currently operates the instance
bin/rails 'operators:revoke[email]'  # take operator access away
bin/rails 'operators:grant[email]'   # give operator access
```

- **The last operator left, or an instance somehow has none:** `grant` a
  known user directly — it doesn't require an existing operator to run it.
- **An operator lost access** (locked account, gone email, anything short of
  a compromise): `list` to confirm who currently holds it, then `grant` a
  replacement.
- **An operatorship needs to be pulled** (compromise, off-boarding, or just
  cleaning up a stale grant): `revoke`.

`revoke` deliberately has **no** last-operator guard the way the panel does
— it's the break-glass path precisely for the case the panel refuses to
handle, so it always does what you ask.
