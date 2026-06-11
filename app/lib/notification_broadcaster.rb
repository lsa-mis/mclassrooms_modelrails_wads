# frozen_string_literal: true

# Refreshes a user's notification surfaces (v2 — supersedes D1's bell-link
# broadcaster). Four broadcasts per refresh:
#
#   - notifications_indicator_avatar     → severity-colored dot on the avatar
#   - notifications_indicator_hamburger  → severity-colored dot on the mobile
#                                          hamburger button
#   - notifications_menu_count_frame     → the [N new] badge inside the user-menu
#                                          Notifications row
#   - notifications-live                 → aria-live SR announcement
#
# Each broadcast runs in its own rescue scope: a failure on ONE surface
# must NOT abort the others. The signature use case this prevents is a
# transient cable adapter hiccup or partial-rendering exception silently
# dropping the other broadcasts mid-refresh, leaving the UI stale.
#
# Architecture note (v2 supersedes D1): we now have FOUR broadcast targets
# vs D1's three, because the standalone bell with severity-glyph + aria-label
# was split into two indicator surfaces (avatar + hamburger) plus an in-menu
# count badge. D1's `notifications_bell_label_frame` is retired — the avatar
# and hamburger now carry static identity-only aria-labels, and notification
# meaning is exposed via the user-menu Notifications row's aria-live region.
#
# `announcement_key` is an I18n key passed straight to `I18n.t`. Two
# canonical values exist today:
#   - notifications.bell.arrival_announcement   ("New notification")
#   - notifications.bell.read_state_announcement ("Notifications updated")
#
# Two callers, one shape:
#   1. ApplicationNotifier#broadcast_notifications_arrival (after_create_commit
#      on the event), called per recipient.
#   2. Account::NotificationsController#broadcast_bell_refresh, called for
#      Current.user after a read-state mutation (mark/unmark, mark_all_read,
#      open, destroy-when-unread).
#
# Performance: the unread breakdown summary is computed ONCE at the top of
# refresh_for and passed to each receiving partial as a `summary:` local.
# This avoids redundant `unread_notification_breakdown` queries that would
# otherwise fire (one per partial that needs it).
module NotificationBroadcaster
  module_function

  def refresh_for(user, announcement_key:)
    stream_key = [ user, :notifications ]
    summary = NotificationBellHelper.unread_notification_summary(user)

    # broadcast_update_to (not _replace_to): each target is a <turbo-frame> and
    # these partials render the frame's CONTENTS, not the frame itself. `replace`
    # swaps the whole frame element away, so repeat broadcasts can't re-target it
    # and the surfaces freeze after the first refresh. `update` swaps the frame's
    # inner content and keeps the frame element addressable for the next refresh.
    safe_broadcast(stream_key, source: "indicator_avatar") do
      Turbo::StreamsChannel.broadcast_update_to(
        stream_key,
        target: "notifications_indicator_avatar",
        partial: "shared/notifications_indicator",
        locals: { summary: summary, surface: :avatar }
      )
    end

    safe_broadcast(stream_key, source: "indicator_hamburger") do
      Turbo::StreamsChannel.broadcast_update_to(
        stream_key,
        target: "notifications_indicator_hamburger",
        partial: "shared/notifications_indicator",
        locals: { summary: summary, surface: :hamburger }
      )
    end

    safe_broadcast(stream_key, source: "menu_count_row") do
      Turbo::StreamsChannel.broadcast_update_to(
        stream_key,
        target: "notifications_menu_count_frame",
        partial: "shared/user_menu_notifications_row",
        locals: { user: user, summary: summary }
      )
    end

    safe_broadcast(stream_key, source: "aria_live") do
      Turbo::StreamsChannel.broadcast_update_to(
        stream_key,
        target: "notifications-live",
        content: I18n.t(announcement_key)
      )
    end
  end

  def safe_broadcast(stream_key, source:)
    yield
  rescue StandardError => e
    Rails.logger.warn("notification broadcast failed (#{source}): #{e.class}: #{e.message}")
    Rails.error.report(
      e,
      handled: true,
      severity: :warning,
      context: { source: "NotificationBroadcaster.#{source}", stream_key: stream_key.inspect }
    )
  end
  private_class_method :safe_broadcast
end
