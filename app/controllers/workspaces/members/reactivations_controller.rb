module Workspaces
  module Members
    # Reactivating a deactivated member. Deactivation is members#destroy.
    class ReactivationsController < ApplicationController
      include WorkspaceScoped

      def create
        @membership = @workspace.memberships.find(params[:member_id])
        authorize @membership, :reactivate?
        @membership.reactivate!(granted_by: Current.user)
        redirect_to workspace_members_path(@workspace), notice: t(".reactivated")
      end
    end
  end
end
