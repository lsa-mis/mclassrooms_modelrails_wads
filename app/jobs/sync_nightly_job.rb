# The 2:30am trigger (config/recurring.yml: nightly_sync). It only enqueues SyncRunJob, which owns
# the one-sync-per-workspace limit; a night that finds a sync already running is skipped.
class SyncNightlyJob < ApplicationJob
  queue_as :default

  def perform
    SyncRunJob.perform_later(Workspace.kept.find_by!(slug: TenancyConfig.shared_workspace_slug))
  end
end
