module Workspaces
  class BrandingsController < ApplicationController
    include WorkspaceScoped

    def edit
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
    end

    def crop
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
      unless @workspace.logo.attached?
        redirect_to edit_workspace_branding_path(@workspace), alert: t("image_crop.no_image")
        nil
      end
    end

    def save_crop
      authorize @workspace, policy_class: Workspaces::BrandingPolicy

      attachment = ActiveStorage::Attachment.find_by(
        record_type: "Workspace",
        record_id: @workspace.id,
        name: "logo"
      )

      unless attachment
        redirect_to edit_workspace_branding_path(@workspace), alert: t("image_crop.no_image")
        return
      end

      crop_params = params.require(:crop).permit(:x, :y, :w, :h).transform_values(&:to_i)
      blob = ActiveStorage::Blob.find(attachment.blob_id)
      blob.update!(metadata: blob.metadata.merge("crop" => crop_params.to_h))
      redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
    end

    def update
      authorize @workspace, policy_class: Workspaces::BrandingPolicy

      # Remove logo (modal remove button)
      if params[:remove_image].present?
        @workspace.logo.purge if @workspace.logo.attached?
        redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
        return
      end

      # Logo upload from the modal (top-level param)
      logo_file = params[:logo]

      if logo_file.present?
        @workspace.logo.attach(logo_file)
        redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
        return
      end

      # Full branding form (nested under workspace)
      if params.key?(:workspace)
        @workspace.logo.attach(params[:workspace][:logo]) if params.dig(:workspace, :logo).present?

        if @workspace.update(branding_params)
          redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
        else
          render :edit, status: :unprocessable_entity
        end
      else
        redirect_to edit_workspace_branding_path(@workspace)
      end
    end

    private

    def branding_params
      params.require(:workspace).permit(:primary_color)
    end
  end
end
