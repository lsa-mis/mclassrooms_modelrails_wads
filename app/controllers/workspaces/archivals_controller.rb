module Workspaces
  # Archived is a state the workspace is in, so it is a singular resource:
  # create archives, destroy restores. Both are idempotent on the model side.
  class ArchivalsController < ApplicationController
    include WorkspaceScoped

    def create
      authorize @workspace, :archive?
      @workspace.archive!
      redirect_to workspaces_path, notice: t(".success")
    end

    def destroy
      authorize @workspace, :unarchive?
      @workspace.unarchive!
      redirect_to workspace_path(@workspace), notice: t(".success")
    end
  end
end
