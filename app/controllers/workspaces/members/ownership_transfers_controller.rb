module Workspaces
  module Members
    # Handing the workspace to another member: the current owner's membership
    # steps down to admin and the target's steps up, in one locked transaction
    # (Membership::Ownership#transfer_ownership_to!).
    class OwnershipTransfersController < ApplicationController
      include WorkspaceScoped

      def create
        @membership = @workspace.memberships.kept.find(params[:member_id])
        authorize @membership, :transfer_ownership?
        current_membership = @workspace.memberships.kept.find_by!(user: Current.user)
        current_membership.transfer_ownership_to!(@membership)
        redirect_to workspace_members_path(@workspace), notice: t(".transferred")
      end
    end
  end
end
