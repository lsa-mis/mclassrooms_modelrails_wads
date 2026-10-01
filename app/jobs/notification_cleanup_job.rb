# frozen_string_literal: true

# Daily cleanup honoring per-user `retention_days`. Unread notifications are
# never deleted regardless of age. Retention is read through
# ApplicationNotifier.preferences_for so a user with no preferences row is
# swept at the same default the index page tells them about.
#
# There is no notification-layer retention floor (PR 5): a security-category
# row expires under the user's retention like any other, and the durable
# record of that event is its ActivityLog row, kept by
# ActivityLogRetentionSweepJob::SECURITY_RETENTION_FLOOR.
#
# Batched delete_all in chunks of 100 so SQLite's writer lock is released
# between rounds. See /docs/developer/notifications (NotificationCleanupJob).
class NotificationCleanupJob < ApplicationJob
  queue_as :low

  # Childless-only, never age-based (#811): deleting an event cascades to its
  # notifications. NOT IN is safe only because event_id is NOT NULL.
  def self.orphan_events
    Noticed::Event.where.not(id: Noticed::Notification.select(:event_id))
  end

  def perform
    attempted = 0
    failed = 0
    last_error = nil

    # includes(:preferences): cleanup_for reads the row through
    # ApplicationNotifier.preferences_for, which is an N+1 without it.
    User.includes(:preferences).find_each do |user|
      attempted += 1
      cleanup_for(user)
    rescue StandardError => e
      # A per-user fault costs that user; a systemic one fails all and re-raises below.
      failed += 1
      last_error = e
      Rails.error.report(e, handled: true, context: { user_id: user.id, job: self.class.name })
    end

    raise last_error if failed.positive? && failed == attempted

    # A partial failure raises nothing, so it is logged here (#944).
    if failed.positive?
      Rails.logger.warn(
        "[#{self.class.name}] swept #{attempted - failed} of #{attempted} users " \
        "(#{failed} failed; last: #{last_error.class})"
      )
    end

    # After the loop so newly emptied events go too; skipped when every user failed.
    prune_orphan_events
  end

  private

  def prune_orphan_events
    self.class.orphan_events.in_batches(of: 100, &:delete_all)
  end

  def cleanup_for(user)
    days = ApplicationNotifier.preferences_for(user).retention_days
    # +2 days of slack against timezone drift; it only ever keeps a row longer.
    cutoff = (days + 2).days.ago

    user.notifications
        .where.not(read_at: nil)
        .where("read_at < ?", cutoff)
        .in_batches(of: 100, &:delete_all)
  end
end
