module SyncRunsHelper
  RUN_TONES = { succeeded: :success, failed: :danger, running: :info }.freeze
  PHASE_TONES = { succeeded: :success, failed: :danger, running: :info, pending: :neutral, skipped: :neutral }.freeze
  COUNTERS = %w[created updated added removed cleared deactivated deleted skipped api_calls rate_limit_sleeps].freeze

  def sync_run_status_badge(run)
    status = run.status.to_sym
    ui :badge, t("sync_runs.status.#{status}"), variant: :soft, tone: RUN_TONES.fetch(status)
  end

  def sync_phase_status_badge(phase)
    status = phase.status.to_sym
    ui :badge, t("sync_runs.phase_status.#{status}"), variant: :soft, tone: PHASE_TONES.fetch(status)
  end

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

  def sync_progress_label(run)
    phase = run.current_phase
    return t("sync_runs.progress.starting") unless phase

    t("sync_runs.progress.step", step: run.steps_done + 1, total: run.steps_total, phase: t("sync_runs.phases.#{phase.key}"))
  end

  def sync_progress_detail(run)
    phase = run.current_phase
    return unless phase&.items_total

    t("sync_runs.progress.items.#{phase.key}", done: number_with_delimiter(phase.items_done.to_i), total: number_with_delimiter(phase.items_total))
  end

  def sync_changes_heading(run)
    if run.running? then t("sync_runs.changes.heading.running")
    elsif run.dry_run? then t("sync_runs.changes.heading.dry_run")
    else t("sync_runs.changes.heading.finished")
    end
  end

  def sync_change_lines(run)
    run.changes_made.map { |kind, count| t("sync_runs.changes.kinds.#{kind}", count:, number: number_with_delimiter(count)) }
  end

  def sync_no_changes_message(run)
    if run.running? then t("sync_runs.changes.none.running")
    elsif run.dry_run? then t("sync_runs.changes.none.dry_run")
    elsif run.succeeded? then t("sync_runs.changes.none.matched")
    else t("sync_runs.changes.none.failed")
    end
  end

  def sync_change_summary(run)
    count = run.change_count
    count.zero? ? t("sync_runs.changes.total.none") : t("sync_runs.changes.total.some", count:, number: number_with_delimiter(count))
  end

  def sync_started_at(run)
    l(run.started_at || run.created_at, format: :short)
  end
end
