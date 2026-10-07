# Runs the pipeline for a run an operator queued or retried (SyncRun.request!, SyncRun#resume!).
class SyncRunJob < ApplicationJob
  queue_as :default

  def perform(sync_run)
    Current.workspace = sync_run.workspace
    Sync::RunPipeline.call(resume_run: sync_run)
  end
end
