module Workspaces
  class JoinLinksController < ApplicationController
    include WorkspaceScoped

    # POST /workspaces/:workspace_slug/join_links
    #
    # Atomically rotates: revokes any existing active link + creates a new one.
    # "Rotate" and "Generate" are the same operation — every successful create
    # leaves exactly one active link.
    def create
      authorize WorkspaceJoinLink

      Workspace.transaction do
        @workspace.join_links.active.find_each(&:revoke!)
        @workspace.join_links.create!(created_by: Current.user)
      end

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
