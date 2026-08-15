module Workspaces
  class MembersController < ApplicationController
    include WorkspaceScoped

    def index
      authorize Membership
      @roles = @workspace.effective_roles
      @assignable_roles = assignable_roles_for(Invitation)

      memberships = @workspace.memberships.for_members_index(
        q: params[:q], role: params[:role], status: params[:status],
        sort: params[:sort], direction: params[:direction]
      )
      invitations = @workspace.invitations.for_members_index(
        q: params[:q], role: params[:role], status: params[:status],
        sort: params[:sort], direction: params[:direction]
      )

      # Invitations first — they're actionable (pending), members are settled;
      # each group honors the active sort within itself (#124). Pagy's offset
      # paginator accepts arrays so the combined list paginates together.
      # Trade-off, stated honestly: BOTH relations fully materialize into Ruby
      # here — acceptable at template scale (tens of rows), and the memory
      # cost grows with the workspace. Revisit as a UNION query when a
      # workspace approaches ~500 combined rows (#124's deferred half).
      combined = invitations.to_a + memberships.to_a
      # Clamp beyond-range pages (stale bookmark, a filter narrowing the set
      # under someone's feet) to the last real page — Pagy 43 hands the view
      # nil rows for an out-of-range request, which 500s the render (found by
      # the #125 filter-on-page-2 spec).
      last_page = [ (combined.size - 1).div(Pagy::OPTIONS[:limit]) + 1, 1 ].max
      page = params[:page].to_i.clamp(1, last_page)
      @pagy, @rows = pagy(:offset, combined, page: page)
    end

    def edit
      @membership = @workspace.memberships.find(params[:id])
      authorize @membership
      @assignable_roles = assignable_roles_for(@membership)
    end

    def update
      @membership = @workspace.memberships.find(params[:id])
      authorize @membership
      role = @workspace.effective_roles.find(membership_params[:role_id])
      authorize_role_grant!(@membership, role)
      @membership.change_role!(role)
      # Frame request → swap just the role cell. Non-Turbo clients → full redirect.
      if request.headers["Turbo-Frame"].present?
        render partial: "role_cell", locals: { membership: @membership }
      else
        redirect_to workspace_members_path(@workspace), notice: t(".success")
      end
    rescue ActiveRecord::RecordInvalid
      # The edit form posts from inside a Turbo Frame; a redirect's flash lives
      # in the layout outside the frame and would be dropped. Answer frame
      # submissions with a toast stream so the error is actually announced.
      message = t(".cannot_demote_last_owner")
      if request.headers["Turbo-Frame"].present?
        render turbo_stream: error_toast(message), status: :unprocessable_entity
      else
        redirect_to workspace_members_path(@workspace), alert: message
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
