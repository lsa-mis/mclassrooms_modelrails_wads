---
title: Notifications — Technical Reference
description: Architecture, broadcast pipeline, persistence schema, and operational concerns for the notifications system
keywords: notifications architecture noticed gem turbo streams broadcasts idempotency value object pundit cleanup digest mailer schema bullet
audience: technical
---

# Notifications — Technical Reference

Implementation reference for the notifications subsystem. The end-user view of the same feature is documented in the [Notifications guide](/docs/notifications).

## Stack at a glance

| Concern | Implementation |
|---|---|
| Event + recipient persistence | [Noticed v2](https://github.com/excid3/noticed) — `noticed_events` + `noticed_notifications` tables |
| Per-event delivery rules | Notifier subclasses under `app/notifiers/` |
| In-app real-time | Turbo Streams broadcast on `[user, :notifications]` channel via `NotificationBroadcaster` |
| Email delivery | `NotificationMailer` (per-event + `digest`); cadence on per-user `notification_preferences` |
| Per-user config | `NotificationPreferences` value object wrapping `user_preferences.notification_preferences` JSONB |
| Background jobs | `DigestMailerJob` (15-min poll), `NotificationCleanupJob` (daily 3 AM UTC) |
| Authorization | `NotificationPolicy` + `Account::NotificationPreferencesPolicy` (Pundit) |

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
| `seen_at` | Reserved for the panel-on-open semantic — currently unused |

There's a composite index `(recipient_id, read_at, created_at)` to back the dropdown's "recent unread + recent read" query, the index page's `?filter=unread`, and the cleanup job's `read_at < cutoff` scan.

### `user_preferences.notification_preferences` (JSONB)

The canonical per-user config. Shape (with database-level defaults applied automatically on row creation):

```json
{
  "notification_types": {
    "security": true,
    "account_access": true,
    "workspace_activity": true,
    "project_activity": true,
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

All inherit from `ApplicationNotifier` (which extends `Noticed::Event`). Each declares its category via the `category` macro:

```ruby
class PasswordChangedNotifier < ApplicationNotifier
  category :security

  deliver_by :email, mailer: "NotificationMailer", method: :password_changed,
             if: ->(recipient) { recipient_pref(:email) == true }

  notification_methods do
    def message = I18n.t("notifications.password_changed.message", user_name: recipient.full_name)
    def url     = main_app.account_connected_accounts_path
  end
end
```

| Notifier | Category | What it dispatches on |
|---|---|---|
| `PasswordChangedNotifier` | `security` | `User#password_digest` change |
| `SignInFromNewDeviceNotifier` | `security` | Login from a previously-unseen browser fingerprint |
| `WorkspaceInvitationReceivedNotifier` | `account_access` | `Invitation` created targeting this user |
| `WorkspaceInvitationAcceptedNotifier` | `account_access` | An invitee accepts the inviter's invitation |
| `WorkspaceInvitationDeclinedNotifier` | `account_access` | An invitee declines |
| `WorkspaceInvitationResentNotifier` | `account_access` | Inviter manually resends |
| `WorkspaceInvitationExpiringSoonNotifier` | `account_access` | Sweep job finds invitations within 24 hours of expiry |
| `WorkspaceRoleChangedNotifier` | `account_access` | Owner changes a member's role |
| `WorkspaceMemberAddedNotifier` | `workspace_activity` | New member joins (fans out to all owners) |
| `ProjectMembershipChangedNotifier` | `project_activity` | Project member role changed |
| `WorkspaceCapacityApproachingNotifier` | `billing` | Sweep job finds a workspace approaching its plan limit |

### Category → notifier types

`ApplicationNotifier.notification_types_for(category)` returns the `Noticed::Notification` STI type strings for that category — used by `NotificationsController#index` for `?category=foo` filtering, and by `NotificationPreferences.security_notifier_types` for retention-floor enforcement.

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

### The three broadcasts

`NotificationBroadcaster.refresh_for(user, announcement_key:)` (in `app/lib/notification_broadcaster.rb`) issues a three-broadcast trio per call:

1. **`broadcast_replace_to`** → `target: "notifications_bell_frame"`, renders `shared/_notifications_bell_button` — updates the badge count
2. **`broadcast_replace_to`** → `target: "notifications_dropdown_frame"`, renders `shared/_notifications_dropdown_list` — refreshes the open-dropdown's recent list
3. **`broadcast_update_to`** → `target: "notifications-live"`, content from `announcement_key` (`notifications.bell.arrival_announcement` or `notifications.bell.read_state_announcement`) — the page-level aria-live region for SR users

The whole method is wrapped in `rescue StandardError`, which `Rails.logger.warn`s + `Rails.error.report(handled: true)`s the failure. A cable adapter outage never blocks notification creation OR controller responses, but the failure reaches your error tracker as a handled exception with a `source:` context tag.

### Two call sites

| Caller | When | Announcement key |
|---|---|---|
| `ApplicationNotifier#broadcast_notifications_arrival` (after_create_commit on the event) | New notification arrives | `arrival_announcement` |
| `NotificationsController#broadcast_bell_refresh` (private) | Read-state mutation (`update`, `open`, `mark_all_read`, `destroy` when previously unread) | `read_state_announcement` |

Both flow through `NotificationBroadcaster.refresh_for` — no duplicate broadcast code lives anywhere else. The fan-out in `broadcast_notifications_arrival` iterates `User.where(id: recipient_ids).find_each` so per-user broadcast failures are isolated (one bad user can't poison the rest).

### Why hook on `Noticed::Event`, not `Noticed::Notification`

Noticed v2 uses `notifications.insert_all!` to fan out per-recipient rows — that bulk insert bypasses ActiveRecord callbacks on the `Notification` class. So `after_create_commit :broadcast_notifications_arrival` lives on `ApplicationNotifier` (the Event class), and the method queries `Noticed::Notification.where(event_id: id, recipient_type: "User").pluck(:recipient_id)` to find the rows that the bulk insert created.

### Frame targets in the DOM

| Frame ID | Lives in | Replaced by |
|---|---|---|
| `notifications_bell_frame` | `shared/_notifications_bell.html.erb` | `_notifications_bell_button.html.erb` |
| `notifications_dropdown_frame` | `shared/_notifications_dropdown.html.erb`, with `target="_top"` so notification links break out of the frame on click | `_notifications_dropdown_list.html.erb` |

The dropdown frame uses `target="_top"` so clicking a notification link navigates the full page (not into the frame), and the panel chrome (header + "See all" link) lives OUTSIDE the broadcast frame so it's never disturbed.

### Focus restoration on broadcast

`notification_dropdown_controller.js` listens for `turbo:before-stream-render` and, when the stream targets `notifications_dropdown_frame`, captures the currently-focused `[data-notification-item]` id pre-render and reapplies focus to the same item post-render. Without this, a user keyboard-navigating with arrow keys would lose focus to `<body>` on every cross-tab read-state change.

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
| `Account::NotificationsController` | `index`, `update` (read-state toggle), `destroy`, `open` (mark read + redirect), `mark_all_read`, `destroy_all_read` | Pundit-gated; calls `broadcast_bell_refresh` on every read-state mutation |
| `Account::NotificationPreferencesController` | `edit`, `update`, `dismiss_banner` | Delegates validation to `NotificationPreferences#merge`; rescues `InvalidChange` → 422 |
| `Account::Preferences::TimezonesController` | `update` | Beacon-path returns 204; explicit-user path (`override=true`) returns Turbo Stream that closes the drawer + announces "Timezone updated" |

## Pundit policies

| Policy | Notes |
|---|---|
| `NotificationPolicy` | Per-record policy gates `update?`/`destroy?`/`open?` by `record.recipient_id == user.id`. `Scope` filters all of `Noticed::Notification` to the current user |
| `Account::NotificationPreferencesPolicy` | Trivial — `edit?`/`update?`/`dismiss_banner?` all return `user.present?` |
| `Account::ThemePreferencesPolicy` | Same shape |
| `Account::TimezonePolicy` | Same shape |

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

`config/environments/test.rb` has several Bullet safelist entries specific to the notifications surface. They're not "ignored warnings" — each documents a deliberate trade-off:

- **`StubAccountAccessNotifier` / `StubSecurityNotifier` unused_eager_loading on `:event` / `:record`** — broadcast renders the dropdown helper which eager-loads `event: :record`; stub notifiers don't traverse those in `#message`, so single-row tests look "unused" to Bullet. Real notifier subtypes do traverse them.
- **`SignInFromNewDeviceNotifier` unused_eager_loading on `:record`** — same pattern, but for the index page which always eager-loads `event.record` for ALL rows. SignInFromNewDevice reads only `event.params`, so when it's the only subtype in a result the include looks wasted.
- **`Invitation :accepted_by` / `:invitable` n_plus_one_query** — `WorkspaceInvitationAcceptedNotifier#message` traverses both; Rails' polymorphic `includes(event: :record)` can't transitively eager-load these without a per-subtype preload step.
- **`Membership :user` / `:workspace` n_plus_one_query** — `WorkspaceMemberAddedNotifier#message` traverses `event.record.user.first_name`; same polymorphic limit.

The dropdown surface is capped at 15 rows (10 unread + 5 read), so the N+1 trade-off is bounded.

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
2. Declare `category :name` (one of `security`, `account_access`, `workspace_activity`, `project_activity`, `billing`)
3. Define `notification_methods do; def message; def url; end` (use `event.record.*` for context)
4. Add `deliver_by :email, ... if:` guards if you want email
5. Add I18n keys under `notifications.<notifier_snake_case>.message`
6. If the notifier's `#message` traverses deep polymorphic associations, expect Bullet flags — safelist entries match the pattern above
7. Dispatch with `NotifierClass.with(record: ...).deliver(recipients)` from wherever the triggering event happens

The category macro and `with` parameter are enough to route the new notifier through the existing preference gates, idempotency, broadcasts, retention, and digest pipeline. No controller or view changes needed.

## Related

- **End-user guide** — [Notifications](/docs/notifications)
- **Architecture overview** — [Architecture](/docs/architecture)
- **Email flows** — [Email Flows](/docs/emails)
