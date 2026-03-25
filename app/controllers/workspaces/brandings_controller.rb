module Workspaces
  class BrandingsController < ApplicationController
    include WorkspaceScoped

    def edit
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
    end

    def update
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
      @workspace.logo.attach(params[:workspace][:logo]) if params.dig(:workspace, :logo).present?

      if @workspace.update(branding_params)
        redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def branding_params
      params.require(:workspace).permit(:primary_color)
    end
  end
end
