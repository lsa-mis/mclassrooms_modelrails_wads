---
title: Notifications — Technical Reference
description: Architecture, broadcast pipeline, persistence schema, and operational concerns for the notifications system
keywords: notifications architecture noticed gem turbo streams broadcasts broadcaster indicator recipients gating idempotency value object pundit cleanup retention digest mailer seen_at quiet hours placeholder deleted record schema bullet
---

# Notifications — Technical Reference

Implementation reference for the notifications subsystem. The end-user view of the same feature is in the **User Guide** version of this doc — switch the mode in the sidebar to view it.

## Stack at a glance

| Concern | Implementation |
|---|---|
| Event + recipient persistence | [Noticed v2](https://github.com/excid3/noticed) — `noticed_events` + `noticed_notifications` tables |
| Per-event delivery rules | Notifier subclasses under `app/notifiers/` |
| In-app real-time | Turbo Streams 4-target broadcast on `[user, :notifications]` channel via `NotificationBroadcaster` |
| Email delivery | `NotificationMailer` (per-event + `digest`); cadence on per-user `notification_preferences` |
| Per-user config | `NotificationPreferences` value object wrapping `user_preferences.notification_preferences` JSONB |
| Background jobs | `DigestMailerJob`, `NotificationCleanupJob` — cadence + queue in `config/recurring.yml` |
| Authorization | `NotificationPolicy` + `Settings::NotificationPreferencesPolicy` (Pundit) |

## Schema

### `noticed_events`

One row per discrete event. Polymorphic `record` association ties the event to whatever caused it (a `User`, an `Invitation`, a `Membership`, etc.).

Key column: `idempotency_key` — a `(notifier_class, record_id, minute_bucket)` string. A **partial unique index** on this column is the atomic source of truth for dedup; concurrent dispatches racing within the same minute lose to `ActiveRecord::RecordNotUnique`, which `ApplicationNotifier#deliver` rescues into the `:deduplicated` sentinel.

### `noticed_notifications`

One row per `(event, recipient)` pair. `recipient` is polymorphic (always `User` in v1). `read_at` is `nil` for unread.

| Column | Purpose |
|---|---|
| `event_id` | FK to `noticed_events` |
| `recipient_type` / `recipient_id` | Polymorphic recipient |
| `type` | STI shape — e.g., `PasswordChangedNotifier::Notification` |
| `read_at` | Nullable timestamp; the read/unread state |
| `seen_at` | First time the recipient surfaced the row in chrome; set by `mark_seen!` from the notification methods mixin |

There's a composite index `(recipient_id, read_at, created_at)` to back the `/account/notifications` index page (default sort + `?filter=unread`), the per-user unread breakdown that drives the bell indicator, and the cleanup job's `read_at < cutoff` scan.

### `user_preferences.notification_preferences` (JSONB)

The canonical per-user config. Shape (with database-level defaults applied automatically on row creation):

```json
{
  "notification_types": {
    "security": true,
    "account_access": true,
    "workspace_activity": true,
    "billing": true
  },
  "delivery_methods": {
    "in_app": { "enabled": true },
    "email":  { "enabled": true, "frequency": "instant" }
  },
  "quiet_hours": {
    "enabled": false,
    "start": "22:00",
    "end": "07:00",
    "active_days": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
  },
  "retention_days": 90
}
```

A user with no `user_preferences` row at all still gets sane defaults because `ApplicationNotifier.preferences_for(user)` falls back to `UserPreferences.new.notification_preferences` (which materializes the schema default).

## Notifier subclasses

All inherit from `ApplicationNotifier` (which extends `Noticed::Event`). Each declares its `category` (drives preference opt-in/opt-out) and its `severity` (drives the bell indicator color) via DSL macros:

```ruby
class PasswordChangedNotifier < ApplicationNotifier
  category :security
  severity :danger

  deliver_by :email, mailer: "NotificationMailer", method: :password_changed,
             if: ->(recipient) { recipient_pref(:email) == true }

  notification_methods do
    def message = I18n.t("notifications.password_changed.message", user_name: recipient.full_name)
    def url     = main_app.settings_connected_accounts_path
  end
end
```

`category` stores as a `String` (compared against JSONB preference keys); `severity` stores as a `Symbol` (used to index into `NotificationBellHelper::SEVERITY_RANK`/`SEVERITY_CLASSES`). Default `severity` is `:info` when a subclass doesn't declare one.

| Notifier | Category | Severity | What it dispatches on |
|---|---|---|---|
| `PasswordChangedNotifier` | `security` | `danger` | `User#password_digest` change |
| `PasskeyAddedNotifier` | `security` | `danger` | Passkey enrollment (`Passkeys::RegistrationsController#verify`) |
| `SignInFromNewDeviceNotifier` | `security` | `danger` | Login from a previously-unseen browser fingerprint |
| `WorkspaceInvitationReceivedNotifier` | `account_access` | `info` | `Invitation` created targeting this user |
| `WorkspaceInvitationAcceptedNotifier` | `workspace_activity` | `success` | An invitee accepts the inviter's invitation |
| `WorkspaceInvitationDeclinedNotifier` | `workspace_activity` | `info` | An invitee declines |
| `WorkspaceInvitationResentNotifier` | `account_access` | `info` | Inviter manually resends |
| `WorkspaceInvitationExpiringSoonNotifier` | `account_access` | `warning` | Sweep job finds invitations within 24 hours of expiry |
| `WorkspaceRoleChangedNotifier` | `account_access` | `info` | Owner changes a member's role |
| `WorkspaceMemberAddedNotifier` | `workspace_activity` | `success` | New member joins (fans out to all owners) |
| `WorkspaceCapacityApproachingNotifier` | `billing` | `warning` | Sweep job finds a workspace approaching its plan limit |

### Category → notifier types

`ApplicationNotifier.notification_types_for(category)` returns the `Noticed::Notification` STI type strings for that category — used by `NotificationsController#index` for `?category=foo` filtering, and by `NotificationPreferences.security_notifier_types` for retention-floor enforcement.

### Preference resolution and the missing-row fallback

`ApplicationNotifier.preferences_for(user)` resolves a `NotificationPreferences` object for any user, **including users with no persisted `user_preferences` row**: it falls back to wrapping `UserPreferences.new.notification_preferences`. Why a transient record instead of a Ruby constant? The `notification_preferences` JSONB column carries a database-level default containing the canonical permission matrix (see `db/schema.rb`), and Rails populates column defaults on the in-memory record — so the schema default stays the single source of truth. Hard-coding the matrix in Ruby would create a second copy that could silently drift from the schema.

This replaced an earlier behavior that wrapped `nil`, which made every category except `security` return `false` from `allow?` — a silent default-deny posture for freshly-created users with no preferences row yet. Incorrect, since the schema default permits in-app delivery for every category.

The method is available as both a class method (backing the per-recipient `recipient_pref` shim inside `notification_methods`) and an instance method (used by class-level `recipients` resolvers).

### In-app gating lives in `recipients`

Noticed 2.9.x deprecates the `:database` delivery method — notification rows are auto-saved by the deliver pipeline itself, so there is no delivery-method conditional to hang an "is in-app enabled for this recipient?" check on. The only place to prevent a `noticed_notifications` row from ever existing is **recipient resolution**: the notifier's `recipients` block filters out users whose `<category>.in_app` preference is `false` (which, for non-security categories, also covers quiet hours via `allow?`). This is the pattern for every notifier that respects in-app preferences; `WorkspaceMemberAddedNotifier` and `WorkspaceCapacityApproachingNotifier` are the two current examples. Combined with the missing-row fallback above, users without a preferences row are correctly treated as opted-in at the column-default level instead of being silently filtered out of every dispatch.

Genuinely per-notifier specifics:

- **`WorkspaceMemberAddedNotifier`** (fires on `Membership` create) is dual-recipient: (1) the added user, (2) all workspace owners, `.uniq`'d so an added user who is already an owner isn't double-notified. The block preloads `:preferences` in one query — per-user `user.preferences` access inside the filter is otherwise an N+1 across the candidate set (Bullet caught it). Email goes **only** to the added user: a `before_enqueue` lambda `throw(:abort)`s unless `recipient_id == event.record.user_id` AND the added user's `workspace_activity.email` pref is `true`. Comparing on the `recipient_id` column (not the loaded association) avoids a per-row association load that Bullet would flag when Noticed's `EventJob` iterates `event.notifications`. Owners never get an immediate email — the digest pipeline is their intended email fallback.
- **`WorkspaceCapacityApproachingNotifier`** (fired by `WorkspaceCapacitySweepJob` when a workspace reaches ≥ 80% of a plan quota; v1 sweeps only the `members` metric) sends to workspace owners filtered by `billing.in_app` — the category is deliberately `billing`, not `security`, so quiet hours suppress these. It overrides `populate_idempotency_key`: the default one-minute bucket is wrong for a recurring sweep (cadence in `config/recurring.yml`), so the override folds `(workspace, metric)` with a **day** bucket. Repeat sweeps in one day dedupe to a single alert; distinct metrics for the same workspace on the same day don't collapse onto each other; the next day's sweep gets a fresh key and delivers again if the workspace is still over threshold.

### Email gating and the `:digest` sentinel

`recipient_pref(:email)` is tri-state: `true` (deliver now), `false` (drop), or the `:digest` sentinel (the item waits for `DigestMailerJob` to pick it up). Email `before_enqueue` guards must therefore compare `== true` explicitly — a truthiness check would let `:digest` fire an instant email, silently defeating the user's digest frequency choice.

### `render_safe_or_placeholder` — the deleted-record contract

Any notifier `message`/`url` body that traverses associations or reads attributes off `event.record` should run inside `render_safe_or_placeholder`. It rescues exactly two shapes, logs at `info`, and renders the `notifications.placeholder` I18n string:

- `ActiveRecord::RecordNotFound` — the resource was destroyed mid-render
- `NoMethodError` **only when the exception's receiver is `nil`** — a chained association is now nil

Everything else propagates: typos and missing methods on non-nil receivers are real bugs and must not be masked as placeholders.

Know the contract's edge: only deletion shapes that surface as a *nil receiver* are caught. `resource.invitable.name` where `invitable` is gone raises `NoMethodError` with `receiver == nil` — caught. A stale FK pointing at a deleted record that still loads as a stub object won't produce a nil receiver and may bubble up as `RecordNotFound` (caught) or some other exception (not caught). `I18n::InvalidLocale` is also NOT rescued — which is why `recipient_locale` validates the stored locale against `I18n.available_locales` before handing it to `I18n.t` (a stored-but-retired locale would otherwise 500 the surface rendering the message).

## Bell indicator + helper

There is no dropdown panel and no standalone bell link. The unread indicator is a small severity-colored **dot** rendered by `shared/_notifications_indicator`: the desktop avatar button carries it at its bottom-right, and the mobile hamburger button carries its twin. The dot's color encodes the highest-severity unread; the numeric `[N new]` badge lives in the user-menu **Notifications** row, which is also the navigation path to `/account/notifications`. The dot itself is purely decorative (`aria-hidden`) — the accessible announcement lives elsewhere (see the broadcast pipeline below).

### `User#unread_notification_breakdown`

One indexed `GROUP BY` query that returns `{ notifier_class_name => unread_count, ... }` for the user — count + severity-source data in a single DB hit:

```ruby
def unread_notification_breakdown
  notifications
    .where(read_at: nil)
    .joins("INNER JOIN noticed_events ON noticed_events.id = noticed_notifications.event_id")
    .group("noticed_events.type")
    .count
end
```

### `NotificationBellHelper`

The helper owns view-token mapping + severity orchestration. The three public surfaces consumers care about:

| Method | Returns | Used by |
|---|---|---|
| `unread_notification_summary(user)` | `{ count:, severity: }` (severity nil when count zero) | The three frame-rendering broadcasts (avatar indicator, hamburger indicator, menu count row); passed in as a `summary:` local from `NotificationBroadcaster` to avoid redundant queries |
| `notification_bell_classes(severity, variant: :icon)` | `{ icon: "text-<severity>" }` for `:icon`; a dot class (`SEVERITY_DOT_CLASSES`) for `:dot` | The indicator partial (`variant: :dot`) — maps severity to the saturated `--color-{severity}` token already used by toasts; `variant:` selects the icon-tint vs. dot-indicator form |
| `avatar_button_aria_label(user, summary = …)` | I18n-composed string ("User menu for Dave. 3 unread notifications, including a security alert.") | Retained from the retired standalone bell; the current avatar button carries a static identity-only label (`navigation.user_menu_label_simple`), so unread phrasing no longer rides the button's accessible name |

`SEVERITY_RANK = { danger: 4, warning: 3, info: 2, success: 1 }` — higher rank wins when multiple severities are unread. `canonical_severity(severity)` clamps any input to one of the four canonical values (defensive coverage for non-production paths; production is already guarded by `ApplicationNotifier.severity`'s DSL).

The helper uses `extend self` so every method is callable BOTH as a module method (`NotificationBellHelper.unread_notification_summary(user)`, used by `NotificationBroadcaster` which has no view context) AND as a public instance method when mixed into a view. Unlike `module_function`, instance-mixed methods stay public, so `helper.foo` works in specs.

### Forced-colors fallback for AAA

Windows High Contrast / `forced-colors: active` overrides author colors with system colors, so the dot's severity fill collapses to a single system color. The indicator partial forces `bg-[Highlight]` under `forced-colors:` so the dot stays visible (WCAG 1.4.11 non-text contrast under that accommodation), and a `drop-shadow` filter keyed to `--color-surface-raised` separates it from arbitrary avatar backgrounds. The dot also always renders — visibility is `opacity-100`/`opacity-0`, so mark-all-read fades it out (`motion-safe:` only) instead of removing the element.

## Idempotency

Every event carries an `idempotency_key` populated by `ApplicationNotifier#populate_idempotency_key` in a `before_create` callback. Default shape:

```
{NotifierClass}_{record_id}_{minute_bucket}
```

Where `minute_bucket = Time.current.to_i / 60`. This means:

- The same notifier + same record dispatched **within the same minute** dedupes to one event
- A dispatch at second 59 and a retry at second 0 of the next minute **both succeed** (different buckets)
- The DB partial unique index enforces the dedup atomically; there's no app-level SELECT-then-INSERT race

Callers can pass `idempotency_key: "custom"` to override the default. If neither `:record` nor an explicit key is supplied, `populate_idempotency_key` raises `ArgumentError` — loud failure beats silent dedup-collapse across distinct events.

`ApplicationNotifier#deliver` returns sentinels:

- `:delivered` on first-send
- `:deduplicated` on `ActiveRecord::RecordNotUnique`

Callers (e.g., `WorkspaceInvitationsController#resend`) branch on this to choose flash copy.

## Broadcast pipeline

The Turbo Streams layer is the cross-tab + arrival real-time backbone.

### Subscription

Every authenticated page subscribes via the layout:

```erb
<%= turbo_stream_from [Current.user, :notifications] %>
```

### The four broadcasts

`NotificationBroadcaster.refresh_for(user, announcement_key:)` (in `app/lib/notification_broadcaster.rb`) issues a four-target broadcast per call. Each frame target is an independent slim partial rendered into its own `<turbo-frame>`, so the surfaces refresh atomically without rewiring unrelated chrome.

1. **`notifications_indicator_avatar`** — the severity-colored dot on the desktop avatar button (`shared/_notifications_indicator`, `surface: :avatar`)
2. **`notifications_indicator_hamburger`** — the dot's twin on the mobile hamburger button (same partial, `surface: :hamburger`)
3. **`notifications_menu_count_frame`** — the `[N new]` badge inside the user-menu **Notifications** row (`shared/_user_menu_notifications_row`)
4. **`notifications-live`** — the page-level `aria-live="polite"` region; content is `I18n.t(announcement_key)` (`notifications.bell.arrival_announcement` or `notifications.bell.read_state_announcement`)

All four use `broadcast_update_to`, never `broadcast_replace_to`. The partials render each frame's **contents**, not the frame element itself — `replace` would swap the whole `<turbo-frame>` away, so repeat broadcasts couldn't re-target it and the surfaces would freeze after the first refresh. `update` swaps the inner content and keeps the frame addressable for the next refresh.

Why four targets: an earlier revision (D1) broadcast a standalone header bell — severity glyph plus a broadcast sr-only phrase inside the bell link's accessible name. That label frame is retired deliberately. The avatar and hamburger buttons now carry **static, identity-only** `aria-label`s; notification semantics are exposed through the user-menu Notifications row and the `aria-live` region instead. The enduring constraint: broadcast frames and live regions stay **outside** a focusable control's accessible-name path, so a control's name never mutates under an AT user mid-session.

Each broadcast runs in its own `safe_broadcast` rescue scope. A failure on ONE surface must NOT abort the others: the real failure mode this prevents is a transient cable adapter hiccup or a partial-rendering exception in an early broadcast silently dropping the rest of the refresh, leaving the UI stale. Each failed broadcast is `Rails.logger.warn`'d and `Rails.error.report(handled: true)`'d with a `source: "NotificationBroadcaster.<surface>"` context tag (`indicator_avatar`, `indicator_hamburger`, `menu_count_row`, `aria_live`), so cable outages reach your error tracker per-surface.

Performance: the unread breakdown summary is computed ONCE at the top of `refresh_for` and passed to each receiving partial as a `summary:` local — avoids the redundant `unread_notification_breakdown` queries that would otherwise fire, one per partial that needs it.

### Two call sites

| Caller | When | Announcement key |
|---|---|---|
| `ApplicationNotifier#broadcast_notifications_arrival` (after_create_commit on the event) | New notification arrives | `arrival_announcement` |
| `Settings::NotificationsController#broadcast_bell_refresh` (private) | Read-state mutation (`update`, `open`, `mark_all_read`, `destroy` when previously unread) | `read_state_announcement` |

Both flow through `NotificationBroadcaster.refresh_for` — no duplicate broadcast code lives anywhere else. The fan-out in `broadcast_notifications_arrival` iterates `User.where(id: recipient_ids).find_each` so per-user broadcast failures are isolated (one bad user can't poison the rest).

### Why hook on `Noticed::Event`, not `Noticed::Notification`

Noticed v2 uses `notifications.insert_all!` to fan out per-recipient rows — that bulk insert bypasses ActiveRecord callbacks on the `Notification` class. So `after_create_commit :broadcast_notifications_arrival` lives on `ApplicationNotifier` (the Event class), and the method queries `Noticed::Notification.where(event_id: id, recipient_type: "User").pluck(:recipient_id)` to find the rows that the bulk insert created.

### Frame targets in the DOM

| Frame ID | Lives in | Contents rendered by |
|---|---|---|
| `notifications_indicator_avatar` | `shared/_user_menu_avatar_button.html.erb` — a positioned sibling of the avatar image inside the button, outside its accessible-name path | `_notifications_indicator.html.erb` (`surface: :avatar`) |
| `notifications_indicator_hamburger` | `shared/_header.html.erb` — inside the mobile hamburger button, same sibling pattern | `_notifications_indicator.html.erb` (`surface: :hamburger`) |
| `notifications_menu_count_frame` | `shared/_user_menu.html.erb` — wraps the Notifications row | `_user_menu_notifications_row.html.erb` |
| `notifications-live` | `shared/_layout_tail.html.erb` — page-level `aria-live="polite"` region | Plain text content via `broadcast_update_to` |

The buttons themselves are OUTSIDE every broadcast frame — they're stable focusable elements. Only the decorative dot and the count badge swap on broadcast, so clicks landing mid-broadcast still hit a live target.

One trap inside `notifications_menu_count_frame`: the Notifications-row link must carry `data-turbo-frame="_top"`. Without it the link navigates its enclosing frame, and the index response has no matching frame — Turbo shows "Content missing".

### Cross-tab read-state sync

The tab that performs a read-state mutation gets its own surfaces refreshed by the direct Turbo Stream response; the broadcasts exist to cover every OTHER tab the user has open. The contract, pinned by `spec/requests/settings/notifications_spec.rb`: every read-state mutation (`update`, `mark_all_read`, `open`, `destroy`-when-unread) must fire `broadcast_update_to` on the `[user, :notifications]` channel for all three frame targets — `notifications_indicator_avatar` (the dot + its severity), `notifications_indicator_hamburger` (its twin), and `notifications_menu_count_frame` (the count badge) — plus the `aria-live` announcement. Each frame is independent, so the surfaces update in isolation: the count badge re-renders even when a dot is already current. `open` on an already-read notification is an idempotent no-op — zero broadcasts.

## NotificationPreferences value object

`app/lib/notification_preferences.rb` wraps the JSONB hash with typed accessors. The two methods you'll touch most:

### `allow?(category:, channel:)` — decision tree

1. Reject unknown category/channel pairs (`false`)
2. If `category == "security"` → `true` (with one exception: if `channel == "email"` and email is disabled, return `false` — a user who turned off all email accepts that security alerts won't email; in-app remains always-on)
3. If `notification_types[category] != true` → `false`
4. If `delivery_methods[channel].enabled != true` → `false`
5. If `channel == "email"` and frequency is not `"instant"` → return `:digest` sentinel (caller queues for `DigestMailerJob`)
6. If `quiet_hours_active?` → `false` (non-security only; security already returned true in step 2)
7. Otherwise → `true`

### `quiet_hours_active?(now: Time.current)`

Reads the user's timezone (or falls back to `Time.zone`), checks today's day-of-week against `active_days`, then evaluates the time-of-day window. Same-day windows (`s <= e`) use `s <= cur < e`; overnight wraps (`s > e`) use `cur >= s || cur < e`. **Empty `active_days` means quiet hours never apply** — a deceptive state the UI surfaces via a Stimulus-driven warning.

That combination — quiet hours `enabled` with zero day chips checked — is deceptive because the form's toggle reads "Enabled" while the runtime treats quiet hours as never active. The preferences form mounts the `quiet_hours_warning` Stimulus controller, which listens for bubbled `change` events across the quiet-hours fieldset (and re-checks on `connect()` so the initial render matches saved server state); whenever the toggle is on and no day is checked, it unhides a warning paragraph. Without it, a user could save that contradictory configuration and walk away believing quiet hours are active when they aren't.

### `merge(changes)`

Validates a partial-change hash (the shape the preferences form posts), coerces strings to booleans + integers, and returns a NEW value object with the changes deep-merged in. Raises `NotificationPreferences::InvalidChange` on any validation failure — the controller catches and responds 422. **The receiver is unchanged on failure** — no half-applied state.

## Controllers

| Controller | Routes | Notes |
|---|---|---|
| `Settings::NotificationsController` | `index`, `update` (read-state toggle), `destroy`, `open` (mark read + redirect), `mark_all_read`, `destroy_all_read` | Pundit-gated; calls `broadcast_bell_refresh` on every read-state mutation |
| `Settings::NotificationPreferencesController` | `edit`, `update` | Delegates validation to `NotificationPreferences#merge`; rescues `InvalidChange` → 422 |
| `Settings::Preferences::TimezonesController` | `update` | Beacon-path returns 204; explicit-user path (`override=true`) returns Turbo Stream that closes the drawer + announces "Timezone updated" |

## Pundit policies

| Policy | Notes |
|---|---|
| `NotificationPolicy` | Per-record policy gates `update?`/`destroy?`/`open?` by `record.recipient_id == user.id`. `Scope` filters all of `Noticed::Notification` to the current user |
| `Settings::NotificationPreferencesPolicy` | Trivial — `edit?`/`update?` both return `user.present?` |
| `Settings::ThemePreferencesPolicy` | Same shape |
| `Settings::TimezonePolicy` | Same shape |

The preference policies look "decorative" (always-true for an authenticated user), but they're the gate that protects against future actions accidentally bypassing authorization — adding a new `:id`-taking action to any of these controllers will still fail-closed.

## Background jobs

Both scheduled in `config/recurring.yml` under the `production:` key — that file is the source of truth for cadence and queue assignment; the values are deliberately not repeated here. Not active in development/test by default.

### `DigestMailerJob`

**Scope strategy**: one indexed range scan against `user_preferences.digest_next_due_at` per run — no per-user polling. The index is **partial** (`WHERE digest_next_due_at IS NOT NULL` in `db/schema.rb`), so users without a digest schedule never appear in the scan at all; a user on `"instant"` frequency has `digest_next_due_at = nil` and is skipped by construction.

For each due user:

1. Computes the recipient's pending notifications since their last digest send (`seen_at: nil`, created since `digest_last_sent_at`, excluding `security` types — security always delivers instantly)
2. If non-empty: dispatches `NotificationMailer.digest(user, notifications)` and stamps `seen_at` on every included notification
3. Updates `digest_last_sent_at` + recomputes `digest_next_due_at` from the user's cadence (`daily` or `weekly`, stored in `notification_preferences`) in their timezone via `next_due_at_in` (digest hour is hardcoded at 8 AM local)

If quiet hours block delivery at the digest time, the digest is held until the window closes.

**`seen_at` semantics**: the `seen_at` stamp in step 2 (a single bulk `update_all`) is the load-bearing dedupe — the next cycle's `where(seen_at: nil)` filter skips stamped rows, so no item ever appears in two consecutive digests. The accepted trade-off: seen is marked at **job run**, not at mail delivery. If the downstream mail delivery job fails after `DigestMailerJob` commits, the user has notifications marked seen but no email — and those items will not re-enter a later digest, because the `seen_at` filter excludes them. Recovery is the in-app surface (the unread indicator still shows them until the user opens them, since `seen_at` is independent of `read_at`) plus the mail job's own retry policy.

### `NotificationCleanupJob`

Per-user retention enforcement. For each user with non-`nil` `retention_days`:

1. Cutoff = `(retention_days + 2).days.ago` (2-day grace so cleanup never deletes today's reads)
2. Delete `Noticed::Notification` where `recipient_id = user.id` AND `read_at < cutoff` AND `read_at IS NOT NULL`
3. **Security floor exception** — notifications whose notifier carries `category :security` are kept for at least 365 days regardless of user retention preference. The floor is defined in `NotificationPreferences::RETENTION_FLOORS` and the job filters via `NotificationPreferences.security_notifier_types`

**Unread is never deleted**, regardless of age: the user hasn't seen the item yet, so the retention clock effectively starts at `read_at`, not `created_at`. A `nil` `retention_days` means "Never" — the user opted out of auto-deletion and the job skips them entirely.

**Batched deletion**: rows go out via `in_batches(of: 100, &:delete_all)`. SQLite serializes write transactions, so a 10k-row delete in one statement could block incoming notification writes for seconds; per-batch transactions release the write lock between rounds, capping any single block at roughly 10 ms.

Uses `delete_all` (not `destroy_all`) because `Noticed::Notification` has no destroy callbacks and no outgoing `dependent:` cascades (the only cascade is *inbound* from `noticed_events`) — `destroy_all` would instantiate every doomed row, fire nonexistent callbacks, and DELETE row-by-row: slower with no behavioral difference. Single DELETE per batch, no row instantiation. The `noticed_events` row remains; `Noticed::Event#has_many :notifications, dependent: :delete_all` handles cascade in the reverse direction.

## Bullet safelists (test env)

`config/environments/test.rb` has several Bullet safelist entries specific to the notifications surface. They're not "ignored warnings" — each documents a deliberate trade-off on the `/account/notifications` index page (which eager-loads `includes(:recipient, event: :record)` for every row):

- **`WorkspaceMemberAddedNotifier::Notification` n_plus_one_query on `:recipient`** — Noticed v2's `EventJob` iterates `event.notifications.each` and accesses each notification's `recipient` (for the `deliver_by :email` lambda's `recipient_pref` check). The library doesn't expose a hook to eager-load `:recipient` on the notifications relation, so this is a structural constraint of the gem. Covers WorkspaceMemberAdded's fan-out to every workspace owner.
- **`WorkspaceCapacityApproachingNotifier::Notification` n_plus_one_query on `:recipient`** — same delivery-layer rationale as above; capacity alerts dispatch to all workspace owners.
- **`SignInFromNewDeviceNotifier` unused_eager_loading on `:record`** — the index page eager-loads `event.record` for every row because every other notifier's `#message` interpolates `event.record.<attr>`. SignInFromNewDevice reads only `event.params`, so when it's the only subtype in a result the include looks wasted. The safelist documents the deliberate trade-off rather than dropping eager-load for all rows.
- **`Membership :user` / `:workspace` n_plus_one_query** — `WorkspaceMemberAddedNotifier#message` traverses `event.record.user.first_name` (record is a Membership). Rails' polymorphic `includes(event: :record)` can't transitively eager-load grandchild associations without a per-subtype preload step.
- **`Invitation :accepted_by` / `:invitable` n_plus_one_query** — `WorkspaceInvitationAcceptedNotifier#message` traverses both (record is an Invitation). Same polymorphic-deep-include limit.

Accepting the per-row traversal cost is the right trade-off versus building a per-subtype preload pipeline for what is fundamentally a polymorphic STI tree.

## Operational concerns

### Monitoring

Watch for:

- **`Rails.error` reports tagged `source: "NotificationBroadcaster.refresh_for"`** — cable adapter outages or partial-render errors. Notification persistence is unaffected, but the real-time UX degrades to "next page load."
- **`Solid Queue` job retries** on `DigestMailerJob` and `NotificationCleanupJob` — queue assignment lives in `config/recurring.yml`. Failed digest sends will retry per the queue's policy.
- **`noticed_events` growth rate** — events are not pruned by `NotificationCleanupJob` (only `noticed_notifications` rows are). Long-lived events with retention'd-away notifications accumulate. Pruning of orphan events is a future cleanup.

### Tuning

- **Retention** is per-user via `notification_preferences.retention_days`. Floors are app-wide via `NotificationPreferences::RETENTION_FLOORS`. Bump the security floor by editing that constant.
- **Digest hour** is hardcoded at 8 AM local in `NotificationPreferences#digest_hour_local`. Per-user configuration was deliberately removed in the v2 redesign — IA simplification.
- **Idempotency window** is 1 minute (the `minute_bucket` divisor). Increasing it widens the dedup horizon. Cross-minute retries by design land in distinct buckets and both succeed.

### Adding a new notifier

1. Subclass `ApplicationNotifier` under `app/notifiers/`
2. Declare `category :name` (one of `security`, `account_access`, `workspace_activity`, `billing`)
3. Declare `severity :level` (one of `:danger`, `:warning`, `:info`, `:success`) — drives the bell color; omitting it defaults to `:info`
4. Define `notification_methods do; def message; def url; end` (use `event.record.*` for context)
5. Add `deliver_by :email, ... if:` guards if you want email
6. Add I18n keys under `notifications.<notifier_snake_case>.message`
7. If the notifier's `#message` traverses deep polymorphic associations, expect Bullet flags — safelist entries match the pattern above
8. Dispatch with `NotifierClass.with(record: ...).deliver(recipients)` from wherever the triggering event happens

The `category` + `severity` macros and the `with` parameter are enough to route the new notifier through the existing preference gates, bell-indicator severity selection, idempotency, broadcasts, retention, and digest pipeline. No controller or view changes needed.

## Related

- **End-user instructions** for the same feature — switch to **User Guide** in the sidebar to view the user-facing companion to this doc
- **Architecture overview** — [Architecture](/docs/developer/architecture)
- **Email flows** — [Email Flows](/docs/user/emails)
