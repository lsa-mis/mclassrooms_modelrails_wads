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

  def sync_duration(seconds)
    return t("sync_runs.not_finished") if seconds.nil?

    ActiveSupport::Duration.build(seconds.round).inspect
  end

  def sync_started_at(run)
    l(run.started_at || run.created_at, format: :short)
  end
end
