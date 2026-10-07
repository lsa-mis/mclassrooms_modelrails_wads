# Read-only sync history for the directory's admins and editors; operators act on it in /operations.
module Admin
  class SyncRunsController < ApplicationController
    include DirectoryScoped

    def index
      authorize SyncRun
      @sync_runs = SyncRun.history_for(Current.workspace)
      @inventory = SyncRun.inventory_for(Current.workspace)
    end

    def show
      @sync_run = SyncRun.for_current_workspace.includes(:sync_phases).find(params[:id])
      authorize @sync_run
    end
  end
end
