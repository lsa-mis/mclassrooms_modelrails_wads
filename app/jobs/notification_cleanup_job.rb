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

  # Which events are orphans — public because it is the contract, not an
  # implementation detail: CHILDLESS-ONLY, never age-based. Deleting an event
  # cascades to every recipient's row through the FK, so age is the one
  # criterion that could take live notifications with it. An event from years
  # ago whose notification is still unread belongs to somebody's list; an
  # event with no rows belongs to nobody and can never be read, rendered, or
  # counted (#811).
  #
  # Asked of noticed_notifications, never of noticed_events.notifications_count,
  # which was deliberately left stale — pruning on that counter would delete
  # events that still have rows. NOT IN is sound here only because
  # noticed_notifications.event_id is NOT NULL; a nullable column would make
  # the predicate unknown and match nothing.
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
      # Per-user data faults (a malformed preferences row) cost that user's
      # sweep, not the cycle. A systemic fault — SQLite's writer lock is
      # global — fails every user and is re-raised below, so Solid Queue
      # records a failure instead of a clean run. There is no retry policy on
      # this job: the recovery is tomorrow's fresh sweep, which re-attempts
      # every user from scratch because nothing here is stamped as done.
      failed += 1
      last_error = e
      Rails.error.report(e, handled: true, context: { user_id: user.id, job: self.class.name })
    end

    raise last_error if failed.positive? && failed == attempted

    # A PARTIAL failure raises nothing — two of three users failing is not
    # `failed == attempted` — and the per-user reports go to Rails.error, so
    # without this line the run reads as a clean sweep to anyone watching the
    # queue (#944). Said once, with the shape of the damage.
    if failed.positive?
      Rails.logger.warn(
        "[#{self.class.name}] swept #{attempted - failed} of #{attempted} users " \
        "(#{failed} failed; last: #{last_error.class})"
      )
    end

    # After the loop, so events this run just emptied are pruned in the same
    # pass. Skipped when every user failed: nothing was deleted, and the fault
    # is systemic (SQLite's writer lock is global), so the prune would only
    # raise a second error over the first.
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
