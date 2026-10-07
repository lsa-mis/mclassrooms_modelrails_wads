module Operations
  module SyncRuns
    class ResumptionsController < BaseController
      include OperatedDirectory

      def create
        sync_run = directory_sync_runs.find(params[:sync_run_id])
        authorize [ :operations, sync_run ], :resume?

        case sync_run.resume!(by: Current.user)
        when :resumed then redirect_to operations_sync_run_path(sync_run), notice: t(".success")
        when :already_running then redirect_to operations_sync_run_path(sync_run), alert: t("operations.sync_runs.already_running")
        else redirect_to operations_sync_run_path(sync_run), alert: t(".not_resumable")
        end
      end
    end
  end
end
