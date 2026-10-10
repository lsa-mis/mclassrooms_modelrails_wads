module Operations
  module SyncRuns
    class ResumptionsController < BaseController
      include OperatedDirectory

      def create
        sync_run = directory_sync_runs.find(params[:sync_run_id])
        authorize [ :operations, sync_run ], :resume?

        if !sync_run.failed?
          redirect_to operations_sync_run_path(sync_run), alert: t(".not_resumable")
        elsif SyncRunJob.perform_later(directory_workspace, resume: sync_run, requested_by: Current.user)
          redirect_to operations_sync_run_path(sync_run), notice: t(".success")
        else
          redirect_to operations_sync_run_path(sync_run), alert: t("operations.sync_runs.not_queued")
        end
      end
    end
  end
end
