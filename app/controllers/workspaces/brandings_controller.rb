module Workspaces
  class BrandingsController < ApplicationController
    include WorkspaceScoped

    def edit
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
    end

    def update
      authorize @workspace, policy_class: Workspaces::BrandingPolicy

      if params[:remove_image].present?
        @workspace.logo.purge if @workspace.logo.attached?
        redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
        return
      end

      if params.dig(:workspace, :logo).present?
        @workspace.logo.attach(params[:workspace][:logo])
      end

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
