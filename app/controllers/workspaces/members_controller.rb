module Workspaces
  class MembersController < ApplicationController
    include WorkspaceScoped

    def index
      authorize Membership
      scope = @workspace.memberships
        .includes(:user, :role)
        .search(params[:q])
        .filter_by_role(params[:role])
        .filter_by_status(params[:status])
        .sorted_by(params[:sort], params[:direction])

      @pagy, @memberships = pagy(:offset, scope)
      @roles = @workspace.effective_roles
      @pending_invitations = @workspace.invitations.pending.includes(:role)
    end

    def edit
      @membership = @workspace.memberships.find(params[:id])
      authorize @membership
      @roles = @workspace.effective_roles
    end

    def update
      @membership = @workspace.memberships.find(params[:id])
      authorize @membership
      role = @workspace.effective_roles.find(membership_params[:role_id])
      @membership.change_role!(role)
      redirect_to workspace_members_path(@workspace), notice: t(".success")
    end

    def destroy
      @membership = @workspace.memberships.find(params[:id])
      authorize @membership
      @membership.deactivate!
      redirect_to workspace_members_path(@workspace), notice: t(".deactivated")
    rescue ActiveRecord::RecordInvalid
      redirect_to workspace_members_path(@workspace), alert: t(".cannot_deactivate_last_owner")
    end

    def reactivate
      @membership = @workspace.memberships.find(params[:id])
      authorize @membership
      @membership.reactivate!
      redirect_to workspace_members_path(@workspace), notice: t(".reactivated")
    end

    def transfer_ownership
      @membership = @workspace.memberships.kept.find(params[:id])
      authorize @membership
      current_membership = @workspace.memberships.kept.find_by!(user: Current.user)
      current_membership.transfer_ownership_to!(@membership)
      redirect_to workspace_members_path(@workspace), notice: t(".transferred")
    end

    private

    def membership_params
      params.require(:membership).permit(:role_id)
    end
  end
end
