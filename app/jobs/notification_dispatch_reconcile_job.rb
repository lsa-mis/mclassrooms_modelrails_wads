# frozen_string_literal: true

# Re-enqueues events whose EventJob never started, stamping first so duplicates
# cannot fan out. A `deliver(..., wait:)` needs a wider GRACE (#927, notifications doc).
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

  # Public so a spec can assert the count; the queue tables are absent in test.
  def self.stuck_event_job_count
    SolidQueue::Job.where(class_name: "Noticed::EventJob").joins(:failed_execution).count
  end

  private

  # A dead worker's executions fail rather than retry (#1065). Logged, not reported:
  # a standing count is a gauge, not an error occurrence.
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
