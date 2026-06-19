module Workspaces
  class MembersController < ApplicationController
    include WorkspaceScoped

    layout "settings"
    settings_context :workspace

    def index
      authorize Membership
      @roles = @workspace.effective_roles

      memberships = @workspace.memberships.for_members_index(
        q: params[:q], role: params[:role], status: params[:status],
        sort: params[:sort], direction: params[:direction]
      )
      invitations = @workspace.invitations.for_members_index(
        q: params[:q], role: params[:role], status: params[:status]
      )

      # Invitations first — they're actionable (pending), members are settled.
      # Pagy's offset paginator accepts arrays so the combined list paginates
      # together; long lists of either kind don't blow the page open.
      combined = invitations.to_a + memberships.to_a
      @pagy, @rows = pagy(:offset, combined)
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
      # Frame request → swap just the role cell. Non-Turbo clients → full redirect.
      if request.headers["Turbo-Frame"].present?
        render partial: "role_cell", locals: { membership: @membership }
      else
        redirect_to workspace_members_path(@workspace), notice: t(".success")
      end
    end

    def destroy
      @membership = @workspace.memberships.find(params[:id])
      authorize @membership

      leaving = @membership.user == Current.user

      @membership.deactivate!

      if leaving
        redirect_to workspaces_path,
                    notice: t("workspaces.members.destroy.left", workspace: @workspace.name)
      else
        redirect_to workspace_members_path(@workspace),
                    notice: t(".deactivated")
      end
    rescue ActiveRecord::RecordInvalid
      if @membership&.user == Current.user
        redirect_to workspaces_path,
                    alert: t("workspaces.members.destroy.cannot_leave_last_owner")
      else
        redirect_to workspace_members_path(@workspace),
                    alert: t(".cannot_deactivate_last_owner")
      end
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
