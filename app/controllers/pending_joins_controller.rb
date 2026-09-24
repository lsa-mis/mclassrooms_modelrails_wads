class PendingJoinsController < ApplicationController
  # The signed-in user's own parked open-link join (Flow B), stored in the
  # session. Both actions act only on Current.user + their own session — there
  # is no other-user or tenant surface — so neither calls Pundit authorize.

  # POST /pending_join — accept the parked join (explicit re-consent for a
  # pre-existing user who wasn't auto-joined).
  def create
    link = pending_join_link
    if link.nil?
      clear_pending_join
      return redirect_to root_path, alert: t(".unavailable")
    end

    workspace = link.workspace

    # Through the LINK, not the workspace: admit re-reads both records inside
    # the write transaction and no-ops on a link revoked since the page loaded
    # (#1061). nil is that refusal, not an error.
    if link.admit(Current.user).nil?
      clear_pending_join
      return redirect_to root_path, alert: t(".unavailable")
    end

    clear_pending_join
    redirect_to workspace_path(workspace), notice: t(".joined", workspace_name: workspace.name)
  rescue Workspace::AlreadyMember, Workspace::AtCapacity
    # Capacity, or a lost race where they were admitted elsewhere first. The
    # resolver already excluded current members, so this is an edge, not the norm.
    clear_pending_join
    redirect_to root_path, alert: t(".could_not_join", workspace_name: workspace.name)
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
