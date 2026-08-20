# frozen_string_literal: true

# Refreshes a user's four notification surfaces (avatar dot, hamburger dot,
# user-menu count badge, aria-live region). Each broadcast is self-rescuing so
# one failing surface never aborts the others; the unread summary is computed
# once and passed to every partial. See /docs/developer/notifications
# (Broadcast pipeline).
module NotificationBroadcaster
  module_function

  def refresh_for(user, announcement_key:)
    stream_key = [ user, :notifications ]
    summary = UnreadNotificationSummary.new(user).to_h

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
