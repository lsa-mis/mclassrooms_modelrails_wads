---
title: Notifications
description: How to read, manage, and configure your in-app notifications
keywords: notifications bell dropdown unread quiet hours email digest categories retention preferences mark read mark unread
---

# Notifications

ModelRails keeps you informed about what's happening across your workspaces, projects, and account — without overwhelming you. This guide covers how to read notifications, mark them as handled, and tune what you receive (and when).

## The bell

You'll find the bell icon in the top-right of every page, next to your avatar.

| What you see | What it means |
|---|---|
| Just the bell | Nothing new — you're caught up |
| Bell + number badge | You have unread notifications. The number shows how many |
| `10+` badge | More than nine unread |

The bell also shows a tooltip ("hidden by Do Not Disturb") when quiet hours are suppressing notifications and you still have unread items.

### Opening the dropdown

Three ways:

- **Click** the bell
- **Cmd+Shift+N** (Mac) or **Ctrl+Shift+N** (Windows/Linux) — works from anywhere on the page
- **Tab** to the bell with your keyboard, then **Enter** or **Space**

The dropdown shows your most recent notifications (up to 10 unread + 5 most recent read). Unread items have a subtle highlighted background and announce as "Unread" to screen readers.

### Navigating the dropdown

Once it's open:

| Key | What it does |
|---|---|
| **↓ / ↑** | Move focus to the next / previous notification |
| **Home** | Jump to the first notification |
| **End** | Jump to the last notification |
| **Enter** | Open the focused notification (marks it read, takes you to the page it links to) |
| **Esc** | Close the dropdown (focus returns to the bell) |

Click "See all notifications" at the top of the dropdown for the full list.

## The full notifications page

Visit `/account/notifications` to see every notification you've received (not just the recent ones).

### Filtering

Use the filter chips at the top to narrow what you see:

- **All** — every notification
- **Unread** — only items you haven't read yet
- **Security**, **Access**, **Workspace**, **Project**, **Billing** — filter by category

### Per-notification actions

Each row has buttons for:

- **Mark as read / Mark as unread** — toggles the read state
- **Delete** — removes the notification entirely

### Bulk actions

At the top of the list:

- **Mark all as read** — clears your unread count without deleting anything
- **Delete all read** — clean up the noise after you've handled things. Unread notifications are preserved

## Real-time updates across tabs

When you mark a notification read on one device or browser tab, all your other open tabs update automatically — the bell badge count drops, the dropdown list refreshes, and screen readers hear a "Notifications updated" announcement. Same when a new notification arrives: every open tab updates without a page refresh.

You don't need to do anything to make this work. It's on by default.

## Notification preferences

Visit **`/account/notification_preferences/edit`** (or open it from your user menu) to tune what you receive.

The page has four sections, each with its own card.

### 1. Your timezone

Shown at the top. The app auto-detects this from your browser when you first sign in, but you can change it anytime by clicking **Change**, picking a new zone, and clicking **Save**. The drawer closes automatically and a confirmation announces "Timezone updated."

Your timezone affects quiet hours scheduling (more on that below) and digest delivery time (8 AM in your local zone).

### 2. Notification types

Choose which categories of events you want to hear about:

| Category | What's in it | Can disable? |
|---|---|---|
| **Security & sign-in** | Password changes, new device sign-ins, account security events | ❌ Always on |
| **Account & access** | Role changes and invitation reminders | ✅ |
| **Workspace activity** | Members joining or changing roles | ✅ |
| **Billing** | Plan changes and usage warnings | ✅ |

**Why security can't be disabled:** Security notifications protect your account. Even if you turn off every other notification type and enable Do Not Disturb, you'll still get sign-in and password-change alerts. This is a hard guarantee the system makes regardless of your settings.

The switch for Security is dimmed to show it can't be changed; the "Always on" label explains why to screen-reader users.

### 3. Delivery method

For each delivery channel, you can opt in or out:

- **In-app** — the bell + dropdown experience described above
- **Email** — sent to your account email address. You can also choose the email cadence:

| Cadence | When emails arrive |
|---|---|
| **Instant** | One email per notification, as it happens |
| **Daily digest** | A single email at 8 AM in your timezone, summarizing the prior day |
| **Weekly digest** | A single email at 8 AM on the same weekday, summarizing the prior week |

Digest emails group notifications by category so they're easy to scan.

### 4. Quiet hours

A do-not-disturb window. When quiet hours are active, in-app notifications are still recorded (you'll see them when the window ends), but you won't be interrupted.

**Security notifications always come through, regardless of quiet hours.** This is the same guarantee as the Notification Types section.

#### Configuring quiet hours

- **Enable quiet hours** — the switch turns the feature on/off
- **From / Until** — the daily time window (e.g., `22:00` to `07:00`). Overnight windows are handled correctly
- **On these days** — which days the window applies. Pick any combination of Mon–Sun

#### The "no days selected" warning

If you turn quiet hours on but uncheck every day, the system can't apply the window — you'll see a warning explaining that quiet hours have no effect in that state. Either pick at least one day, or turn quiet hours off entirely.

### 5. Advanced

- **Auto-delete read notifications after** — how long to keep read notifications before deleting them. Options: 30, 60, 90, 180, 365 days, or Never. Security alerts are always kept for at least 1 year regardless of this setting

## What carries across devices

Your preferences (notification types, delivery methods, quiet hours, retention, timezone) are stored on your account, so they apply on every device you sign in from. The read/unread state of individual notifications is also shared — marking a notification read on your phone clears it on your laptop too.

## Frequently asked

**Why didn't I get an email for a notification I see in the bell?**
Likely because your email delivery for that category is off, your email digest cadence is Daily or Weekly (so the email is queued up for the next digest run), or quiet hours are active.

**Can I get security alerts to my phone via SMS?**
Not yet. SMS and push notifications are on the roadmap; the current channels are in-app and email.

**Can I undo "Mark all as read"?**
No. Mark-all-read is a single atomic operation. If you need to recover a specific notification, the data isn't lost — it's still in your notifications list with `read_at` set — so you can find it via the filters and mark it unread again.

**Can I undo "Delete all read"?**
No. Deleted notifications are permanently removed. Use this when you're certain you don't need to refer back to read notifications.

## Related

- **Implementation details** for system administrators — switch to **Developer Guide** in the sidebar to see the technical reference (schema, broadcast pipeline, background jobs, operational tuning)
- **Account management** — for changing your email, password, and avatar, see the [Account Management guide](/docs/user/accounts)
- **Workspaces** — for inviting members and configuring workspace settings, see the [Workspace Administration guide](/docs/user/workspaces)

Have a question this guide doesn't cover? File an issue or reach out to your administrator.
