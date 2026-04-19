module Workspaces
  class BrandingsController < ApplicationController
    include WorkspaceScoped
    include CropCoordinatable

    def hub
      authorize @workspace, :update?, policy_class: Workspaces::BrandingPolicy

      @source = if params[:source].present? && @workspace.available_logo_sources.include?(params[:source])
                  params[:source]
      else
                  @workspace.logo_source
      end

      is_user = false
      has_image = @workspace.logo.attached?
      current_hue = @workspace.primary_color || 210
      display_url = has_image ? url_for(@workspace.logo) : nil

      render partial: "shared/identity_picker_hub",
        locals: {
          model: @workspace,
          form_url: workspace_branding_path(@workspace),
          hub_url: hub_workspace_branding_path(@workspace),
          current_source: @source,
          has_color_picker: true,
          available_sources: @workspace.available_logo_sources,
          is_user: is_user,
          has_image: has_image,
          current_hue: current_hue,
          display_url: display_url,
          gravatar_url: nil,
          initials: @workspace.initials,
          hub_title: t("identity_picker.choose_workspace_logo")
        },
        layout: false
    end

    def edit
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
    end

    def update
      authorize @workspace, policy_class: Workspaces::BrandingPolicy

      # Guard: reject invalid source values
      if params[:avatar_source].present? && !@workspace.available_logo_sources.include?(params[:avatar_source])
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.append("toast-cards",
              partial: "shared/toast_card",
              locals: { type: :error, message: t("workspaces.brandings.source_unavailable") }),
                   status: :forbidden
          end
          format.html { redirect_to edit_workspace_branding_path(@workspace), alert: t("workspaces.brandings.source_unavailable") }
        end
        return
      end

      # JS saveCrop sends "avatar"/"avatar_original" to match User flow —
      # accept those as aliases for logo/logo_original
      cropped_image = params[:avatar] || params[:logo]
      original_image = params[:avatar_original] || params[:logo_original]

      # Handle logo attachments (from identity picker crop flow)
      if cropped_image.present?
        @workspace.logo.attach(cropped_image)
        @workspace.logo_source = "upload"
      end

      if original_image.present?
        @workspace.logo_original.attach(original_image)
      end

      # Store crop coordinates
      if params[:crop_coordinates].present? && @workspace.logo_original.attached?
        coords = safe_parse_coordinates(params[:crop_coordinates])
        if coords
          blob = @workspace.logo_original.blob
          blob.update!(metadata: blob.metadata.merge("crop" => coords))
        end
      end

      # Handle avatar_source change (from identity picker removePhoto flow)
      # When JS removePhoto sends avatar_source=initials, purge logo blobs immediately
      if params[:avatar_source].present? && cropped_image.blank?
        source = params[:avatar_source]
        @workspace.logo_source = source
        if source != "upload"
          @workspace.logo.purge if @workspace.logo.attached?
          @workspace.logo_original.purge if @workspace.logo_original.attached?
        end
      end

      # Handle primary_color from the identity picker hub form.
      # The modal sends primary_color as a top-level param (not nested under workspace[...]),
      # matching how the User avatars controller handles it.
      if params[:primary_color].present?
        @workspace.primary_color = params[:primary_color].to_i
      end

      # Crop save (logo file present) keeps modal open; hub save (no logo) closes it
      @close_modal = cropped_image.blank?

      if @workspace.update(branding_params)
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to edit_workspace_branding_path(@workspace), notice: t(".success") }
        end
      else
        @workspace.logo.purge if cropped_image.present?
        @workspace.logo_original.purge if original_image.present?

        error_message = @workspace.errors.full_messages.to_sentence

        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.append("toast-cards",
              partial: "shared/toast_card",
              locals: { type: :error, message: error_message }),
                   status: :unprocessable_content
          end
          format.html { render :edit, status: :unprocessable_content }
        end
      end
    end

    def destroy
      authorize @workspace, policy_class: Workspaces::BrandingPolicy

      @workspace.logo.purge if @workspace.logo.attached?
      @workspace.logo_original.purge if @workspace.logo_original.attached?
      @workspace.update!(logo_source: "initials")

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_workspace_branding_path(@workspace), notice: t(".success") }
      end
    end

    private

    def branding_params
      params.require(:workspace).permit(:primary_color)
    rescue ActionController::ParameterMissing
      {}
    end
  end
end
