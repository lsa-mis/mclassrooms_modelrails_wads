# frozen_string_literal: true

# Bounds the activity log at 12 months (#438, panel-decided 2026-08-14).
#
# Why a sweep and not keep-forever: the trail is best-effort BY DESIGN
# (CLAUDE.md deviation #4 — writes rescue rather than fail the business
# operation), so it is not compliance-grade evidence, and retaining it
# forever would make the system's behavior contradict its own guarantee —
# exactly what a fork owner would misread as one. An unbounded high-write
# table on single-host SQLite is also a backup/VACUUM problem discovered at
# the worst time. A regulated fork that needs longer retention changes ONE
# line (and should also read deviation #4: promoting the trail to
# compliance-grade means moving the write inside the business transaction).
#
# This job is the documented door through the ActivityLog immutability
# guarantee: rows are readonly once persisted (#604), relation-level writes
# are fenced by spec/code_smells/activity_log_immutability_spec.rb, and this
# job is registered there in `allowed_bypasses` with its reason — the
# carve-out the guard reserved for exactly this decision.
#
# Batched delete_all per the house pattern (NotificationCleanupJob): SQLite
# serializes writers; per-batch transactions release the lock between rounds.
# ActivityLog has no destroy callbacks or dependent cascades, so delete_all
# instantiates nothing.
class ActivityLogRetentionSweepJob < ApplicationJob
  queue_as :default

  RETENTION_WINDOW = 12.months

  def perform
    ActivityLog.where(created_at: ...RETENTION_WINDOW.ago).in_batches(of: 100, &:delete_all)
  end
end
