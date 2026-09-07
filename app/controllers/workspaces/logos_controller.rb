module Workspaces
  # The logo picker hub, lazy-loaded into the Profile page's modal. Saves post
  # to workspaces#update, where the logo lives; this resource only shows the picker.
  class LogosController < ApplicationController
    include WorkspaceScoped

    def show
      authorize @workspace, policy_class: Workspaces::LogoPolicy
      identity = @workspace.identity

      render partial: "shared/identity_picker_hub",
        locals: {
          identity: identity,
          model: @workspace,
          form_url: workspace_path(@workspace),
          hub_url: workspace_logo_path(@workspace),
          current_source: identity.resolve_source(params[:source])
        },
        layout: false
    end
  end
end
