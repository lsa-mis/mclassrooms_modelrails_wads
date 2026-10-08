# Runs the pipeline for one attempt of a run (SyncRun.request!, #resume!, SyncNightlyJob); a superseded or
# duplicate job finds the attempt already claimed and does nothing.
class SyncRunJob < ApplicationJob
  queue_as :default

  def perform(sync_run, attempt)
    unless sync_run.claim_execution(attempt)
      return Rails.logger.info("[sync] skipped sync run #{sync_run.id} attempt #{attempt}: superseded or already running")
    end

    Current.workspace = sync_run.workspace
    Sync::RunPipeline.call(resume_run: sync_run.reload)
  end
end
