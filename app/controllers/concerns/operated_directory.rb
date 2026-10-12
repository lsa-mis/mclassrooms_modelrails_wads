# The shared directory as an operator reaches it: through their operated workspaces, never Current.workspace.
module OperatedDirectory
  extend ActiveSupport::Concern

  private

  def directory_workspace
    @directory_workspace ||= operated_workspaces.find_by!(slug: TenancyConfig.shared_workspace_slug)
  end

  def directory_sync_runs = SyncRun.where(workspace: directory_workspace)
end
