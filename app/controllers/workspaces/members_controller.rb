module Workspaces
  class MembersController < ApplicationController
    include WorkspaceScoped

    def index
      authorize Membership
      @memberships = @workspace.memberships.includes(:user, :role)
    end

    def edit
      @membership = @workspace.memberships.find(params[:id])
      authorize @membership
      @roles = @workspace.effective_roles
    end

    def update
      @membership = @workspace.memberships.find(params[:id])
      authorize @membership
      role = Role.find(params[:membership][:role_id])
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
      @membership = @workspace.memberships.find(params[:id])
      authorize @membership
      current_membership = @workspace.memberships.kept.find_by!(user: Current.user)
      current_membership.transfer_ownership_to!(@membership)
      redirect_to workspace_members_path(@workspace), notice: t(".transferred")
    end
  end
end
