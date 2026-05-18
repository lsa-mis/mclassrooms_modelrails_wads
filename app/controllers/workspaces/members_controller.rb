module Workspaces
  class MembersController < ApplicationController
    include WorkspaceScoped

    def index
      authorize Membership
      @roles = @workspace.effective_roles

      memberships = filtered_memberships
      invitations = filtered_invitations

      # Invitations first — they're actionable (pending), members are settled.
      # Pagy's array adapter paginates the combined collection so long lists
      # of either kind don't blow the page open.
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

    # Memberships filtered by the index page's search/role/status/sort params.
    # When the status filter is "pending", memberships are excluded entirely
    # (pending = invitations only).
    def filtered_memberships
      return Membership.none if params[:status] == "pending"

      @workspace.memberships
        .includes(:user, :role)
        .search(params[:q])
        .filter_by_role(params[:role])
        .filter_by_status(params[:status])
        .sorted_by(params[:sort], params[:direction])
    end

    # Pending invitations filtered by the same search/role params as members.
    # Hidden when status filter selects an exclusively-membership state
    # (active or deactivated). Invitations have no full_name/sort_by.
    def filtered_invitations
      return Invitation.none if %w[active deactivated].include?(params[:status])

      scope = @workspace.invitations.pending.includes(:role)
      scope = scope.where("LOWER(email) LIKE ?", "%#{params[:q].to_s.downcase}%") if params[:q].present?
      scope = scope.joins(:role).where(roles: { slug: params[:role] }) if params[:role].present?
      scope
    end
  end
end
