class SyncNightlyJob < ApplicationJob
  queue_as :default

  def perform
    SyncRunJob.request(Workspace.kept.find_by!(slug: TenancyConfig.shared_workspace_slug))
  end
end
