# DURATION must exceed any real sync, queue wait included, or the one-at-a-time limit lapses mid-sync.
class SyncRunJob < ApplicationJob
  DURATION = 12.hours

  queue_as :default
  limits_concurrency to: 1, key: ->(workspace, **) { workspace }, duration: DURATION, on_conflict: :discard

  # Solid Queue stores nothing for a request it drops, so that job comes back with no provider id.
  def self.request(workspace, **)
    job = perform_later(workspace, **)
    return :not_queued unless job
    return :queued if job.provider_job_id

    Rails.logger.info("[sync] request for #{workspace.slug} dropped: a sync is already queued or running")
    :already_running
  end

  def perform(workspace, resume: nil, requested_by: nil)
    Current.workspace = workspace
    SyncRun.fail_abandoned(workspace)

    run = resume&.reload || SyncRun.create!(workspace:, dry_run: SyncRun.dry_run_by_default?, status: :running,
                                            started_at: Time.current)
    return if resume && !run.retryable?

    audit(run, resume ? "sync_run.resumed" : "sync_run.requested", requested_by) if requested_by
    Sync::RunPipeline.call(run:)
  end

  private

  def audit(run, action, actor)
    result = Curation::Apply.call(record: run, actor:, action:)
    Rails.logger.warn("[sync] audit row for sync run #{run.id} not written: #{result.errors.to_sentence}") unless result.success?
  end
end
