# Every sync goes through here (nightly, Run now, Retry). Solid Queue runs at most one per workspace and
# discards a request made while one is running; DURATION must exceed any real sync, or the limit lapses.
class SyncRunJob < ApplicationJob
  DURATION = 3.hours

  queue_as :default
  limits_concurrency to: 1, key: ->(workspace, **) { workspace }, duration: DURATION, on_conflict: :discard

  def perform(workspace, resume: nil, requested_by: nil)
    Current.workspace = workspace
    SyncRun.fail_abandoned(workspace)

    run = resume&.reload || SyncRun.create!(workspace:, dry_run: SyncRun.dry_run_by_default?, status: :running,
                                            started_at: Time.current)
    return if resume && !run.failed?

    audit(run, resume ? "sync_run.resumed" : "sync_run.requested", requested_by) if requested_by
    Sync::RunPipeline.call(resume_run: run)
  end

  private

  def audit(run, action, actor)
    result = Curation::Apply.call(record: run, actor:, action:)
    Rails.logger.warn("[sync] audit row for sync run #{run.id} not written: #{result.errors.to_sentence}") unless result.success?
  end
end
