module Workspaces
  # Flow A (Reshape 2a): an *existing* authenticated user joins a workspace via
  # a shareable link. Flow B (new user via link, opening the signup gate) is
  # Reshape 2b — not yet built. See docs/reshape-2-per-workspace-join-policy-spec.md.
  class JoinsController < ApplicationController
    before_action :set_workspace_and_link

    # GET /workspaces/:slug/joins/:token
    # Renders a confirmation page so URL prefetch / link unfurlers can't
    # trigger a join. The POST below is what actually admits.
    def show
      # @workspace + @link set in before_action; view renders confirmation.
    end

    # POST /workspaces/:slug/joins/:token
    def create
      @workspace.admit(Current.user, role: @workspace.default_self_join_role)
      redirect_to workspace_path(@workspace), notice: t(".joined", workspace: @workspace.name)
    rescue ActiveRecord::RecordInvalid => e
      if e.message =~ /already a member/i
        # Already in: this is a no-op, not an error — land them in the workspace.
        redirect_to workspace_path(@workspace), notice: t(".already_member", workspace: @workspace.name)
      else
        # Capacity, etc. — surface the model message cleanly.
        redirect_to root_path, alert: e.message
      end
    end

    private

    # Looks up the workspace + the active link. Collapses "no workspace",
    # "no link", "link revoked", "policy not open", and "instance allowlist
    # excludes :open_link" into one neutral error — never reveals which
    # condition failed (deny information leakage about workspace existence
    # or join policy).
    def set_workspace_and_link
      @workspace = Workspace.find_by(slug: params[:workspace_slug])
      @link = @workspace&.join_links&.active&.find_by(token: params[:token])

      unless @workspace && @link && @workspace.open_join?
        redirect_to root_path, alert: t("workspaces.joins.invalid_or_revoked")
      end
    end
  end
end
