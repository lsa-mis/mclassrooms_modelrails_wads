module Operations
  class SyncRunsController < BaseController
    include OperatedDirectory

    def index
      authorize [ :operations, SyncRun ]
      @sync_runs = SyncRun.history_for(directory_workspace)
      @inventory = SyncRun.inventory_for(directory_workspace)
      @in_progress = SyncRun.in_progress_for?(directory_workspace)
    end

    def show
      @sync_run = directory_sync_runs.includes(:sync_phases).find(params[:id])
      authorize [ :operations, @sync_run ]
      @in_progress = SyncRun.in_progress_for?(directory_workspace)
    end

    def create
      authorize [ :operations, SyncRun ]

      if SyncRun.request!(workspace: directory_workspace, by: Current.user) == :requested
        redirect_to operations_sync_run_path(directory_sync_runs.latest), notice: t(".success")
      else
        redirect_to operations_sync_runs_path, alert: t("operations.sync_runs.already_running")
      end
    end
  end
end
