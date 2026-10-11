module Admin
  class SyncRunsController < ApplicationController
    include DirectoryScoped

    def index
      authorize SyncRun
      @sync_runs = SyncRun.history_for(Current.workspace)
      @latest = SyncRun.most_recent_for(Current.workspace)
      @inventory = SyncRun.inventory_for(Current.workspace)
      @typical = SyncRun.typical_duration_for(Current.workspace)
    end

    def show
      @sync_run = SyncRun.for_current_workspace.includes(:sync_phases).find(params[:id])
      authorize @sync_run
      @typical = SyncRun.typical_duration_for(Current.workspace)
    end
  end
end
