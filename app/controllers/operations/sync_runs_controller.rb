module Operations
  class SyncRunsController < BaseController
    include OperatedDirectory

    def index
      authorize [ :operations, SyncRun ]
      @sync_runs = SyncRun.history_for(directory_workspace)
      @inventory = SyncRun.inventory_for(directory_workspace)
    end

    def show
      @sync_run = directory_sync_runs.includes(:sync_phases).find(params[:id])
      authorize [ :operations, @sync_run ]
    end

    def create
      authorize [ :operations, SyncRun ]

      if SyncRunJob.perform_later(directory_workspace, requested_by: Current.user)
        redirect_to operations_sync_runs_path, notice: t(".success")
      else
        redirect_to operations_sync_runs_path, alert: t("operations.sync_runs.not_queued")
      end
    end
  end
end
