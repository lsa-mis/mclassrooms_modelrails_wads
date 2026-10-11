module SyncRunsHelper
  RUN_TONES = { succeeded: :success, failed: :danger, running: :info }.freeze
  PHASE_TONES = { succeeded: :success, failed: :danger, running: :info, pending: :neutral, skipped: :neutral }.freeze
  # Every counter a phase writes (count(:key) in app/lib/sync), in display order; the helper spec keeps it whole.
  COUNTERS = %w[created updated added removed cleared deactivated deleted skipped api_calls rate_limit_sleeps].freeze

  def sync_run_status_badge(run)
    status = run.status.to_sym
    ui :badge, t("sync_runs.status.#{status}"), variant: :soft, tone: RUN_TONES.fetch(status)
  end

  def sync_phase_status_badge(phase)
    status = phase.status.to_sym
    ui :badge, t("sync_runs.phase_status.#{status}"), variant: :soft, tone: PHASE_TONES.fetch(status)
  end

  # For a run or a step: how long it took, how long it has been running, or neither.
  def sync_duration(record)
    if record.duration_seconds
      localized_duration(record.duration_seconds)
    elsif record.running? && record.started_at
      t("sync_runs.running_for", duration: localized_duration(Time.current - record.started_at))
    else
      t("sync_runs.not_finished")
    end
  end

  def localized_duration(seconds)
    parts = ActiveSupport::Duration.build(seconds.round).parts
    words = []
    words << t("sync_runs.duration.days", count: parts[:days]) if parts[:days]
    words << t("sync_runs.duration.hours", count: parts[:hours]) if parts[:hours]
    words << t("sync_runs.duration.minutes", count: parts[:minutes]) if parts[:minutes]
    words << t("sync_runs.duration.seconds", count: parts.fetch(:seconds, 0)) if parts[:seconds] || words.empty?
    words.to_sentence
  end

  def sync_started_at(run)
    l(run.started_at || run.created_at, format: :short)
  end
end
