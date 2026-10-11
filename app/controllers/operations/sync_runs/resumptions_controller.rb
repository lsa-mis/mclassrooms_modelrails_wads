module Operations
  module SyncRuns
    class ResumptionsController < BaseController
      include OperatedDirectory

      def create
        sync_run = directory_sync_runs.find(params[:sync_run_id])
        authorize [ :operations, sync_run ], :resume?

        outcome = sync_run.retryable? ? SyncRunJob.request(directory_workspace, resume: sync_run, requested_by: Current.user) : :not_resumable
        redirect_to operations_sync_run_path(sync_run), **flash_for(outcome)
      end

      private

      def flash_for(outcome)
        case outcome
        when :queued then { notice: t("operations.sync_runs.resumptions.create.success") }
        when :not_resumable then { alert: t("operations.sync_runs.resumptions.create.not_resumable") }
        when :already_running then { alert: t("operations.sync_runs.already_running") }
        else { alert: t("operations.sync_runs.not_queued") }
        end
      end
    end
  end
end
