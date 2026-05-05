# frozen_string_literal: true

# Scheduled sweep that emits `WorkspaceCapacityApproachingNotifier` for every
# kept workspace that has reached >= 80% of its `max_members` quota. The
# Notifier resolves recipients (all workspace owners) via its class-level
# `recipients` block, so this job dispatches once per workspace; Noticed
# fans out the per-owner notification rows.
#
# Cadence: every 12 hours (see `config/recurring.yml`). Combined with the
# Notifier's day-bucket per-(workspace, metric) idempotency override, owners
# receive at most one capacity alert per workspace per metric per day.
#
# Projects-metric coverage is intentionally OUT OF SCOPE for v1. Although
# `Workspace#max_projects` exists in the schema, scoping the alert volume,
# tier-aware messaging, and copy decisions for the projects threshold is its
# own pass — keeping this PR focused on the notification scheduling layer
# avoids conflating the two changes. Adding a `:projects` branch is a small
# additive change once the projects-cap UX direction is settled.
class WorkspaceCapacitySweepJob < ApplicationJob
  queue_as :default

  THRESHOLD = 0.8

  def perform
    Workspace.kept.find_each do |workspace|
      sweep_members_metric(workspace)
      # Projects-metric check pending v1.x — see class-level docs above.
    end
  end

  private

  def sweep_members_metric(workspace)
    limit = workspace.max_members
    return unless limit

    current = workspace.memberships.kept.count
    return if current < (limit * THRESHOLD)

    # `deliver(nil)` defers recipient resolution to the Notifier's class-level
    # `recipients` block, which returns every workspace owner filtered by
    # `billing.in_app` preference. Single event row per workspace + metric.
    WorkspaceCapacityApproachingNotifier.with(
      record: workspace,
      metric: "members",
      current: current,
      limit: limit
    ).deliver(nil)
  end
end
