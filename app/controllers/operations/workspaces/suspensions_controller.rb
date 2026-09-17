module Operations
  module Workspaces
    # The model's guard (Suspendable#suspend!/#unsuspend!) makes a repeat
    # submit a no-op; the notice reports the resulting state (locked/
    # unlocked), which is true either way.
    class SuspensionsController < BaseController
      before_action :set_workspace

      def create
        authorize [ :operations, @workspace ], :suspend?
        @workspace.suspend!
        redirect_to operations_workspace_path(@workspace), notice: t(".success")
      end

      def destroy
        authorize [ :operations, @workspace ], :unsuspend?
        @workspace.unsuspend!
        redirect_to operations_workspace_path(@workspace), notice: t(".success")
      end

      private

      def set_workspace
        @workspace = operated_workspaces.find_by!(slug: params[:workspace_slug])
      end
    end
  end
end
