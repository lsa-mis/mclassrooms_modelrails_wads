module Workspaces
  class BrandingsController < ApplicationController
    include WorkspaceScoped
    before_action :require_owner_or_admin

    def edit
    end

    def update
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

    def require_owner_or_admin
      membership = @workspace.memberships.kept.find_by(user: Current.user)
      unless membership&.role&.slug&.in?(%w[owner admin])
        redirect_to workspace_path(@workspace), alert: t("workspaces.unauthorized")
      end
    end
  end
end
