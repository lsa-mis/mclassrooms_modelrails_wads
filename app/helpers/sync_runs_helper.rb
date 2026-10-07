module SyncRunsHelper
  RUN_TONES = { succeeded: :success, failed: :danger, running: :info, queued: :info, stalled: :warning }.freeze
  PHASE_TONES = { succeeded: :success, failed: :danger, running: :info, pending: :neutral, skipped: :neutral }.freeze
  COUNTERS = %w[created updated deactivated api_calls rate_limit_sleeps].freeze

  def sync_run_status_badge(run)
    status = run.display_status
    ui :badge, t("sync_runs.status.#{status}"), variant: :soft, tone: RUN_TONES.fetch(status)
  end

  def sync_phase_status_badge(phase)
    status = phase.status.to_sym
    ui :badge, t("sync_runs.phase_status.#{status}"), variant: :soft, tone: PHASE_TONES.fetch(status)
  end

  def sync_duration(seconds)
    return t("sync_runs.not_finished") if seconds.nil?

    ActiveSupport::Duration.build(seconds.round).inspect
  end

  def sync_started_at(run)
    run.started_at ? l(run.started_at, format: :short) : t("sync_runs.not_started")
  end
end
