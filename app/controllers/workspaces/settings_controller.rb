module Workspaces
  class SettingsController < ApplicationController
    include WorkspaceScoped

    def edit
      authorize @workspace, policy_class: Workspaces::SettingsPolicy
    end

    def update
      authorize @workspace, policy_class: Workspaces::SettingsPolicy
      if @workspace.update(settings_params)
        redirect_to edit_workspace_settings_path(@workspace), notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def settings_params
      params.require(:workspace).permit(:max_members, :max_teams)
    end
  end
end
