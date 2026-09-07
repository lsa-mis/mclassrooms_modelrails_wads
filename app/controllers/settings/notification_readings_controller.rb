# frozen_string_literal: true

module Settings
  # Mark all read: readings for every unread notification at once — the bulk
  # twin of Settings::Notifications::ReadingsController, which reads one.
  class NotificationReadingsController < ApplicationController
    def create
      authorize Noticed::Notification, :mark_all_read?, policy_class: NotificationPolicy
      # Single atomic UPDATE: WHERE clause is evaluated once, rows un-marked
      # concurrently can't slip past a moving cursor (the in_batches race
      # the panel flagged), and every row gets the same timestamp instead
      # of per-batch drift. Per-user volume here is bounded by retention
      # caps — if it ever grows, route the heavy lift to PR-5's sweep job.
      now = Time.current
      Current.user.notifications.where(read_at: nil)
                                .update_all(read_at: now, updated_at: now)
      # Cross-tab read-state sync; see /docs/developer/notifications (Cross-tab read-state sync).
      NotificationBroadcaster.refresh_for(Current.user, announcement_key: "notifications.bell.read_state_announcement")
      redirect_to settings_notifications_path, notice: t(".success")
    end
  end
end
