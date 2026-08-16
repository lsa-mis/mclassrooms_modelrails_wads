# frozen_string_literal: true

# Daily cleanup honoring per-user `retention_days`. Unread notifications are
# never deleted regardless of age, and `:security` notifications keep a 1-year
# floor (`NotificationPreferences::RETENTION_FLOORS` is canonical). Batched
# delete_all — SQLite serializes writers.
# See /docs/developer/notifications (NotificationCleanupJob).
class NotificationCleanupJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each do |user|
      cleanup_for(user)
    end
  end

  private

  def cleanup_for(user)
    prefs = user.preferences&.notification_preferences_object
    return unless prefs

    days = prefs.retention_days
    return if days.nil?  # "Never" — user opted out of auto-delete

    cutoff = (days + 2).days.ago
    security_floor_cutoff = NotificationPreferences::RETENTION_FLOORS["security"].ago
    security_types = NotificationPreferences.security_notifier_types
                       .map { |name| "#{name}::Notification" }

    scope = user.notifications
                .where.not(read_at: nil)
                .where("read_at < ?", cutoff)

    scope = if security_types.any?
      # For security-typed notifications, require they're also past the
      # 1-year floor before deletion. Non-security notifications follow
      # only the user retention.
      scope.where(
        "type NOT IN (?) OR read_at < ?",
        security_types,
        security_floor_cutoff
      )
    else
      scope
    end

    scope.in_batches(of: 100, &:delete_all)
  end
end
