module NotificationsHelper
  RECENT_UNREAD_LIMIT = 10
  RECENT_READ_LIMIT = 5

  # Recent notifications for the bell dropdown — at most 10 unread plus 5
  # most recent read, both ordered newest-first. Eager-loads `event` (every
  # notifier's `#message` reads it); per-subtype `event.record` traversal
  # may N+1 a single row but the bounded page size keeps the impact small,
  # and the `SignInFromNewDeviceNotifier` exception is already covered by
  # `config/environments/test.rb`'s safelist.
  def recent_notifications_for_dropdown(user)
    unread = user.notifications.where(read_at: nil)
                 .includes(event: :record)
                 .order(created_at: :desc)
                 .limit(RECENT_UNREAD_LIMIT)
    read = user.notifications.where.not(read_at: nil)
               .includes(event: :record)
               .order(created_at: :desc)
               .limit(RECENT_READ_LIMIT)
    (unread.to_a + read.to_a).sort_by { |n| -n.created_at.to_f }
  end
end
