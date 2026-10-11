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
      outcome = SyncRunJob.request(directory_workspace, requested_by: Current.user)
      redirect_to operations_sync_runs_path, **flash_for(outcome)
    end

    private

    def flash_for(outcome)
      case outcome
      when :queued then { notice: t("operations.sync_runs.create.success") }
      when :already_running then { alert: t("operations.sync_runs.already_running") }
      else { alert: t("operations.sync_runs.not_queued") }
      end
    end
  end
end
