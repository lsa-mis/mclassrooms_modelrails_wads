module Workspaces
  class JoinLinksController < ApplicationController
    include WorkspaceScoped

    # POST /workspaces/:workspace_slug/join_links
    #
    # Atomically rotates: revokes any existing active link + creates a new one.
    # "Rotate" and "Generate" are the same operation — every successful create
    # leaves exactly one active link. The revoke-then-create ordering and the
    # IMMEDIATE transaction (which serializes concurrent rotates on SQLite) keep
    # the invariant; a partial unique index enforces it at the DB level too.
    def create
      authorize WorkspaceJoinLink

      link = nil
      Workspace.transaction do
        @workspace.join_links.active.find_each(&:revoke!)
        link = @workspace.join_links.create!(created_by: Current.user)
      end

      # Show-once: the plaintext token exists only on this freshly-built record
      # (the column stores a digest). Carry the full URL in the encrypted,
      # unlogged flash for a single render, then it's gone for good.
      flash[:join_link_url] = workspace_join_url(@workspace, token: link.plaintext_token)
      redirect_to edit_workspace_settings_path(@workspace), notice: t(".rotated")
    end

    # DELETE /workspaces/:workspace_slug/join_links/:id
    def destroy
      authorize WorkspaceJoinLink

      link = @workspace.join_links.find(params[:id])
      link.revoke!

      redirect_to edit_workspace_settings_path(@workspace), notice: t(".revoked")
    end
  end
end
