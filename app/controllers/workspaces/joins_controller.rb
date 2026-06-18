module Workspaces
  # Two flows go through this controller:
  #   Flow A (Reshape 2a) — existing authenticated user joins via the link.
  #   Flow B (Reshape 2b) — unauthenticated visitor; stash token, redirect to
  #     signup; claim the workspace on email verification.
  # See docs/reshape-2-per-workspace-join-policy-spec.md.
  class JoinsController < ApplicationController
    allow_unauthenticated_access
    before_action :set_workspace_and_link

    # GET /workspaces/:slug/joins/:token
    # Renders a confirmation page so URL prefetch / link unfurlers can't
    # trigger a join. The POST below is what actually admits (or stashes).
    def show
      # @workspace + @link set in before_action; view renders confirmation.
    end

    # POST /workspaces/:slug/joins/:token
    def create
      if authenticated?
        admit_authenticated_user
      else
        stash_for_signup
      end
    end

    private

    def admit_authenticated_user
      @workspace.admit(Current.user, role: @workspace.default_self_join_role)
      redirect_to workspace_path(@workspace), notice: t("workspaces.joins.create.joined", workspace: @workspace.name)
    rescue ActiveRecord::RecordInvalid => e
      if e.message =~ /already a member/i
        # Already in: no-op, land them in the workspace.
        redirect_to workspace_path(@workspace), notice: t("workspaces.joins.create.already_member", workspace: @workspace.name)
      else
        # Capacity, etc. — surface the model message cleanly.
        redirect_to root_path, alert: e.message
      end
    end

    # Flow B entry: park the validated token on the session so
    # SignupPolicy.allows_signup? (via ApplicationController#signups_open?)
    # opens the gate, then redirect through registration. The token is
    # transferred from session to the email Authentication during signup
    # (registrations_controller, omniauth_callbacks) and claimed at email
    # verification (Settings::ConnectedAccountsController#verify).
    def stash_for_signup
      session[:pending_join_token] = @link.token
      redirect_to new_registration_path, notice: t("workspaces.joins.create.register_first", workspace: @workspace.name)
    end

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
