# frozen_string_literal: true

# Daily cleanup that honors per-user `retention_days` from
# `notification_preferences`. Deletes READ notifications past the user's
# retention threshold (with a 2-day grace period). Unread notifications are
# never deleted regardless of age — the user hasn't seen them yet, so the
# retention clock effectively starts at read_at.
#
# Security floor: notifications from `:security` category notifiers
# (PasswordChangedNotifier, SignInFromNewDeviceNotifier, ...) are kept for
# at least 1 year regardless of user retention preference.
# `NotificationPreferences::RETENTION_FLOORS[:security]` is the canonical
# duration; override there if compliance requirements change.
#
# Batched in chunks of 100: SQLite serializes write transactions, and a
# 10k-row delete in one statement could block incoming notifications for
# seconds. Per-batch transactions release the write lock between rounds,
# capping any single block to ~10ms.
#
# Per-batch deletion uses `delete_all` rather than `destroy_all`: Aaron
# Patterson confirmed in the panel review that Noticed::Notification has
# no destroy callbacks and no outgoing `dependent:` cascades (the only
# cascade is INBOUND from noticed_events). `destroy_all` would instantiate
# every doomed row, fire (non-existent) callbacks, and DELETE row-by-row —
# slower with no behavioral difference. Same justification the
# destroy_all_read controller action already documents.
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
