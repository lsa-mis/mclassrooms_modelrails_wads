# frozen_string_literal: true

# Bounds the activity log (#438) — now in TWO grades:
#   * workspace-domain rows (Trackable): best-effort to write, swept at 12 months.
#   * account-security rows (ActivityLog::SECURITY_ACTIONS): retained for at
#     least SECURITY_RETENTION_FLOOR, and never less than the general window
#     (see security_cutoff). This floor REPLACED the notification-layer floor,
#     which PR 5 removed (notifications lifecycle arc, 2026-08/09) — deleting
#     or shortening it silently destroys the system's only credential-event record.
#     The floor is about RETENTION only; the write guarantee is the caller's
#     (strict for credential mutations, best-effort for new-device sign-in).
# This job is the registered bypass through the ActivityLog immutability guard
# (#604). Batched delete_all — SQLite serializes writers.
# See /docs/developer/architecture (Activity Tracking).
class ActivityLogRetentionSweepJob < ApplicationJob
  queue_as :default

  RETENTION_WINDOW = 12.months
  SECURITY_RETENTION_FLOOR = 365.days

  def perform
    ActivityLog.where(created_at: ...RETENTION_WINDOW.ago)
               .where.not(action: ActivityLog::SECURITY_ACTIONS)
               .in_batches(of: 100, &:delete_all)
    ActivityLog.where(action: ActivityLog::SECURITY_ACTIONS)
               .where(created_at: ...security_cutoff)
               .in_batches(of: 100, &:delete_all)
  end

  private

  # The EARLIER of the two cutoffs, so a security row is never deleted while a
  # non-security row of the same age is kept. The constants are equal in an
  # ordinary year, but Duration#ago is calendar-aware: across a Feb 29,
  # 12.months.ago reaches a day further back than 365.days.ago and the floor
  # would otherwise invert. Taking the min also keeps the floor honest if a
  # fork lengthens RETENTION_WINDOW.
  def security_cutoff
    [ SECURITY_RETENTION_FLOOR.ago, RETENTION_WINDOW.ago ].min
  end
end
