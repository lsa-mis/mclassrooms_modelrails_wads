# frozen_string_literal: true

# Bounds the activity log at 12 months (#438): the trail is best-effort BY
# DESIGN, not compliance-grade evidence, and this job
# is the registered bypass through the ActivityLog immutability guard (#604).
# Batched delete_all — SQLite serializes writers.
# See /docs/developer/architecture (Activity Tracking).
class ActivityLogRetentionSweepJob < ApplicationJob
  queue_as :default

  RETENTION_WINDOW = 12.months

  def perform
    ActivityLog.where(created_at: ...RETENTION_WINDOW.ago).in_batches(of: 100, &:delete_all)
  end
end
