---
title: Notifications — Technical Reference
description: Architecture, broadcast pipeline, persistence schema, and operational concerns for the notifications system
keywords: notifications architecture noticed gem turbo streams broadcasts idempotency value object pundit cleanup digest mailer schema bullet
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
| Background jobs | `DigestMailerJob` (15-min poll), `NotificationCleanupJob` (daily 3 AM UTC) |
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

## Bell indicator + helper

The bell IS the indicator — there is no separate dropdown panel. A small solid bell glyph sits at the bottom-right of the avatar when there are unread notifications; the glyph color encodes the highest-severity unread.

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
| `unread_notification_summary(user)` | `{ count:, severity: }` (severity nil when count zero) | The three partial-rendering broadcasts (avatar button, bell, menu count); passed in as a `summary:` local from `NotificationBroadcaster` to avoid redundant queries |
| `notification_bell_classes(severity)` | `{ icon: "text-<severity>" }` | The bell partial — maps severity to the saturated `--color-{severity}` token already used by toasts |
| `avatar_button_aria_label(user, summary = …)` | I18n-composed string ("User menu for Dave. 3 unread notifications, including a security alert.") | The avatar button partial; accepts a precomputed summary so the broadcaster's shared query isn't redone |

`SEVERITY_RANK = { danger: 4, warning: 3, info: 2, success: 1 }` — higher rank wins when multiple severities are unread. `canonical_severity(severity)` clamps any input to one of the four canonical values (defensive coverage for non-production paths; production is already guarded by `ApplicationNotifier.severity`'s DSL).

The helper uses `extend self` so every method is callable BOTH as a module method (`NotificationBellHelper.unread_notification_summary(user)`, used by `NotificationBroadcaster` which has no view context) AND as a public instance method when mixed into a view. Unlike `module_function`, instance-mixed methods stay public, so `helper.foo` works in specs.

### Forced-colors fallback for AAA

Windows High Contrast / `forced-colors: active` overrides author colors with system colors, so the bell's severity fill collapses to a single system color. The partial forces `text-[ButtonText]` under `forced-colors:` so the glyph stays visible (WCAG 1.4.11 non-text contrast under that accommodation). A stacked white drop-shadow outline (three 2px white shadows; black in dark mode) keeps the bell legible against arbitrary avatar backgrounds.

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

### The three broadcasts (D1)

`NotificationBroadcaster.refresh_for(user, announcement_key:)` (in `app/lib/notification_broadcaster.rb`) issues a three-target broadcast trio per call. Each broadcast targets an independent slim partial wrapped in its own turbo-frame, so the surfaces refresh atomically without rewiring unrelated chrome.

1. **`broadcast_replace_to`** → `target: "notifications_bell_label_frame"`, renders `shared/_notifications_bell_label` — refreshes the sr-only `aria-label` text inside the standalone header bell link so AT users hear the new unread count + severity phrase on their next focus traversal
2. **`broadcast_replace_to`** → `target: "notifications_bell_indicator_frame"`, renders `shared/_notifications_bell` — refreshes the severity-colored bell glyph overlay inside the bell link
3. **`broadcast_update_to`** → `target: "notifications-live"`, content from `announcement_key` (`notifications.bell.arrival_announcement` or `notifications.bell.read_state_announcement`) — updates the page-level `aria-live="polite"` region for SR users

Each broadcast runs in its own `safe_broadcast` rescue scope. A failure on ONE surface must NOT abort the others: the real failure mode this prevents is a transient cable adapter hiccup or a partial-rendering exception in the first broadcast silently dropping the rest of the refresh. Each failed broadcast is `Rails.logger.warn`'d and `Rails.error.report(handled: true)`'d with a `source: "NotificationBroadcaster.<surface>"` context tag, so cable outages reach your error tracker per-surface.

Performance: the unread breakdown summary is computed ONCE at the top of `refresh_for` and passed to each receiving partial as a `summary:` local — avoids 2 redundant `unread_notification_breakdown` queries that would otherwise fire (one per partial that needs it).

### Two call sites

| Caller | When | Announcement key |
|---|---|---|
| `ApplicationNotifier#broadcast_notifications_arrival` (after_create_commit on the event) | New notification arrives | `arrival_announcement` |
| `NotificationsController#broadcast_bell_refresh` (private) | Read-state mutation (`update`, `open`, `mark_all_read`, `destroy` when previously unread) | `read_state_announcement` |

Both flow through `NotificationBroadcaster.refresh_for` — no duplicate broadcast code lives anywhere else. The fan-out in `broadcast_notifications_arrival` iterates `User.where(id: recipient_ids).find_each` so per-user broadcast failures are isolated (one bad user can't poison the rest).

### Why hook on `Noticed::Event`, not `Noticed::Notification`

Noticed v2 uses `notifications.insert_all!` to fan out per-recipient rows — that bulk insert bypasses ActiveRecord callbacks on the `Notification` class. So `after_create_commit :broadcast_notifications_arrival` lives on `ApplicationNotifier` (the Event class), and the method queries `Noticed::Notification.where(event_id: id, recipient_type: "User").pluck(:recipient_id)` to find the rows that the bulk insert created.

### Frame targets in the DOM (D1)

| Frame ID | Lives in | Replaced by |
|---|---|---|
| `notifications_bell_label_frame` | `shared/_notifications_bell_link.html.erb` (wraps the sr-only aria-label span) | `_notifications_bell_label.html.erb` |
| `notifications_bell_indicator_frame` | `shared/_notifications_bell_link.html.erb` (sibling of the label frame inside the bell link) | `_notifications_bell.html.erb` |
| `notifications-live` | Layout-level `aria-live="polite"` region | Plain text content via `broadcast_update_to` |

The bell link itself is OUTSIDE every broadcast frame — it's a stable focusable element. Only the sr-only label span and the severity overlay swap on broadcast, so clicks landing mid-broadcast still hit a live target.

There is no longer a dropdown panel; the bell link routes directly to `/account/notifications`, and the avatar opens the existing 2-item user menu (identity block + sign out).

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

### `merge(changes)`

Validates a partial-change hash (the shape the preferences form posts), coerces strings to booleans + integers, and returns a NEW value object with the changes deep-merged in. Raises `NotificationPreferences::InvalidChange` on any validation failure — the controller catches and responds 422. **The receiver is unchanged on failure** — no half-applied state.

## Controllers

| Controller | Routes | Notes |
|---|---|---|
| `Settings::NotificationsController` | `index`, `update` (read-state toggle), `destroy`, `open` (mark read + redirect), `mark_all_read`, `destroy_all_read` | Pundit-gated; calls `broadcast_bell_refresh` on every read-state mutation |
| `Settings::NotificationPreferencesController` | `edit`, `update`, `dismiss_banner` | Delegates validation to `NotificationPreferences#merge`; rescues `InvalidChange` → 422 |
| `Settings::Preferences::TimezonesController` | `update` | Beacon-path returns 204; explicit-user path (`override=true`) returns Turbo Stream that closes the drawer + announces "Timezone updated" |

## Pundit policies

| Policy | Notes |
|---|---|
| `NotificationPolicy` | Per-record policy gates `update?`/`destroy?`/`open?` by `record.recipient_id == user.id`. `Scope` filters all of `Noticed::Notification` to the current user |
| `Settings::NotificationPreferencesPolicy` | Trivial — `edit?`/`update?`/`dismiss_banner?` all return `user.present?` |
| `Settings::ThemePreferencesPolicy` | Same shape |
| `Settings::TimezonePolicy` | Same shape |

The preference policies look "decorative" (always-true for an authenticated user), but they're the gate that protects against future actions accidentally bypassing authorization — adding a new `:id`-taking action to any of these controllers will still fail-closed.

## Background jobs

Both scheduled in `config/recurring.yml` under the `production:` key. Not active in development/test by default.

### `DigestMailerJob`

```yaml
digest_mailer:
  class: DigestMailerJob
  queue: default
  schedule: every 15 minutes
```

Polls `user_preferences` for rows where `digest_next_due_at <= Time.current` (indexed). For each due user:

1. Computes the recipient's pending notifications since their last digest send
2. If non-empty: dispatches `NotificationMailer.digest(user, notifications)`
3. Updates `digest_last_sent_at` + recomputes `digest_next_due_at` from the user's cadence (`daily` or `weekly`) in their timezone (digest hour is hardcoded at 8 AM local)

If the user is on `"instant"` frequency, `digest_next_due_at` is `nil` and they're skipped. If quiet hours block delivery at the digest time, the digest is held until the window closes.

### `NotificationCleanupJob`

```yaml
notification_cleanup:
  class: NotificationCleanupJob
  queue: default
  schedule: every day at 3am
```

Per-user retention enforcement. For each user with non-`nil` `retention_days`:

1. Cutoff = `(retention_days + 2).days.ago` (2-day grace so cleanup never deletes today's reads)
2. Delete `Noticed::Notification` where `recipient_id = user.id` AND `read_at < cutoff` AND `read_at IS NOT NULL` (unread never deleted)
3. **Security floor exception** — notifications whose notifier carries `category :security` are kept for at least 365 days regardless of user retention preference. The floor is defined in `NotificationPreferences::RETENTION_FLOORS` and the job filters via `NotificationPreferences.security_notifier_types`

Uses `delete_all` (not `destroy_all`) because `Noticed::Notification` has no destroy callbacks — single DELETE query, no row instantiation. The `noticed_events` row remains; `Noticed::Event#has_many :notifications, dependent: :delete_all` handles cascade in the reverse direction.

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
- **`Solid Queue` job retries** on `DigestMailerJob` and `NotificationCleanupJob` — both run on `queue: default`. Failed digest sends will retry per the queue's policy.
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
