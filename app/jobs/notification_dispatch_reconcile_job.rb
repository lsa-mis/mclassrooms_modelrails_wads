# frozen_string_literal: true

# The recovery half of the #927 dispatch watermark. `Noticed::EventJob` stamps
# `noticed_events.dispatched_at` the moment it starts (see
# `config/initializers/noticed.rb`), so an event still carrying NULL after the
# grace window is one whose enqueue never landed: the rows committed, the
# recipient can see the notification, the idempotency key is burned — and the
# email and broadcast legs never ran.
#
# Only the never-enqueued gap. An event whose job was claimed is already
# stamped, so this sweep never touches it. What happens to that job afterwards
# is not this job's business — `Noticed::EventJob` now carries its own retry
# policy (config/initializers/noticed.rb, #1065), so a claimed job that raises
# is retried three times before it lands in `solid_queue_failed_executions`.
# What no retry can cover is a worker process that dies: Solid Queue FAILS a
# pruned process's claimed executions rather than releasing them. This job
# reports the count of both at the end of its run, because it is already
# scheduled and this app ships no Mission Control UI.
#
# THE SWEEP STAMPS THE ROW ITSELF, before enqueuing. Its enqueue is the one
# retry an event gets. Without the stamp, a delivery queue backed up past the
# 15-minute cadence would hand cycle N+1 the same unstamped row and fan a
# second copy of every email out to every recipient. Stamping first rather than
# after the enqueue makes that impossible in the other direction too: if the
# enqueue raises, the row is already stamped and is never retried, and the
# per-row rescue below reports it — a lost retry that is visible beats a
# duplicate fan-out that is not.
#
# GRACE is well past any plausible enqueue latency and short enough that a
# recovered notification is late rather than missing. MAX_LOOKBACK bounds the
# other end: a row that can never be stamped (a deserialization discard, a
# fork's hand-written row) would otherwise be re-enqueued every cycle forever.
# The two together are also why the migration backfills pre-existing rows.
#
# One constraint on forks: noticed's `deliver(..., wait:)` / `wait_until:`
# deliberately enqueues EventJob for later, which this sweep would read as a
# lost enqueue and re-deliver early. No dispatch in this app uses them; a fork
# that adds one must widen GRACE past its longest wait, or exclude it here.
#
# Mirrors NotificationCleanupJob's shape: attempted/failed counters, per-row
# rescue reported through Rails.error, and a re-raise when every attempt failed
# so a systemic fault (SQLite's writer lock is global) is recorded as a job
# failure instead of logged as a successful cycle.
class NotificationDispatchReconcileJob < ApplicationJob
  # `default`, not `low`: queue.yml charters `low` as work nobody is waiting on,
  # and this re-delivers a notification that already failed to arrive once. Same
  # reasoning that keeps the two workspace notifier sweeps off `low` (#894).
  queue_as :default

  GRACE = 5.minutes
  MAX_LOOKBACK = 24.hours

  def perform
    attempted = 0
    recovered = 0
    failed = 0
    last_error = nil

    undispatched.find_each do |event|
      attempted += 1
      recover(event)
      recovered += 1
    rescue StandardError => e
      failed += 1
      last_error = e
      Rails.error.report(e, handled: true, context: { event_id: event.id, job: self.class.name })
    end

    if attempted.positive?
      Rails.logger.info(
        "#{self.class.name}: recovered #{recovered} of #{attempted} undispatched events (#{failed} failed)"
      )
    end

    raise last_error if failed.positive? && failed == attempted

    report_failed_event_jobs
  end

  # How many Noticed::EventJob executions are parked in Solid Queue's failed
  # table. Public because the number is the contract — the message below is
  # only how it reaches a human, and the queue tables do not exist in the test
  # database, so this is the seam a spec can speak to.
  def self.stuck_event_job_count
    SolidQueue::Job.where(class_name: "Noticed::EventJob").joins(:failed_execution).count
  end

  private

  # The retry policy (#1065) covers a job that raises. It cannot cover a worker
  # process that dies: Solid Queue FAILS a pruned process's claimed executions
  # rather than releasing them, so those never re-enter the queue — and this
  # app ships no Mission Control UI to notice. This job already runs on a
  # schedule and already writes a summary, so it is the cheapest honest place
  # to say the number out loud.
  #
  # Rails.logger, not Rails.error.report: a standing count is an operational
  # fact, not an error occurrence. Reporting it every cycle would turn the
  # error stream into a gauge that never clears.
  def report_failed_event_jobs
    stuck = self.class.stuck_event_job_count
    return unless stuck.positive?

    Rails.logger.warn(
      "#{self.class.name}: #{stuck} Noticed::EventJob execution(s) sitting in " \
      "solid_queue_failed_executions — retries exhausted, or a worker died mid-claim; " \
      "these need a hand"
    )
  rescue StandardError => e
    # An observability read must never fail the reconcile it rides along with.
    Rails.error.report(e, handled: true, context: { job: self.class.name, probe: "failed_event_jobs" })
  end

  # Stamp, then enqueue — see the note above on why this order and not the
  # reverse. `update_column` skips callbacks and validations deliberately: this
  # is bookkeeping on a gem model, not a domain write.
  def recover(event)
    event.update_column(:dispatched_at, Time.current)
    Noticed::EventJob.perform_later(event)
  end

  # `notifications_count: 1..` rather than `where.not(… 0)`: an event that
  # reached nobody is the artifact #928 is about and there is no recipient for a
  # re-enqueue to reach, and the range form also excludes a NULL count without
  # leaning on NULL-unsafe `!=`.
  def undispatched
    Noticed::Event
      .where(dispatched_at: nil)
      .where(created_at: MAX_LOOKBACK.ago..GRACE.ago)
      .where(notifications_count: 1..)
  end
end
