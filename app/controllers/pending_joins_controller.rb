class PendingJoinsController < ApplicationController
  # The signed-in user's own parked open-link join (Flow B), stored in the
  # session. Both actions act only on Current.user + their own session — there
  # is no other-user or tenant surface — so neither calls Pundit authorize.

  # POST /pending_join — accept the parked join (explicit re-consent for a
  # pre-existing user who wasn't auto-joined).
  def create
    workspace = pending_join_workspace
    if workspace.nil?
      clear_pending_join
      return redirect_to root_path, alert: t(".unavailable")
    end

    workspace.admit(Current.user, role: workspace.default_self_join_role)
    clear_pending_join
    redirect_to workspace_path(workspace), notice: t(".joined", workspace: workspace.name)
  rescue Workspace::AlreadyMember, Workspace::AtCapacity
    # Capacity, or a lost race where they were admitted elsewhere first. The
    # resolver already excluded current members, so this is an edge, not the norm.
    clear_pending_join
    redirect_to root_path, alert: t(".could_not_join", workspace: workspace.name)
  end

  # DELETE /pending_join — dismiss the parked join.
  def destroy
    clear_pending_join
    redirect_back fallback_location: root_path, notice: t(".dismissed")
  end

  private

  def clear_pending_join
    session.delete(:pending_join_token)
  end
end
