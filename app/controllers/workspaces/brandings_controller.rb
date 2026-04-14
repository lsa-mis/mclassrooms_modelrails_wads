module Workspaces
  class BrandingsController < ApplicationController
    include WorkspaceScoped

    def edit
      authorize @workspace, policy_class: Workspaces::BrandingPolicy
    end

    def update
      authorize @workspace, policy_class: Workspaces::BrandingPolicy

      # Remove logo (from identity picker or form)
      if params[:remove_image].present?
        @workspace.logo.purge if @workspace.logo.attached?
        @workspace.logo_original.purge if @workspace.logo_original.attached?
        redirect_to edit_workspace_branding_path(@workspace), notice: t(".success")
        return
      end

      # Handle logo attachments (from identity picker crop flow)
      if params[:logo].present?
        @workspace.logo.attach(params[:logo])
      end

      if params[:logo_original].present?
        @workspace.logo_original.attach(params[:logo_original])
      end

      # Store crop coordinates
      if params[:crop_coordinates].present? && @workspace.logo_original.attached?
        coords = safe_parse_coordinates(params[:crop_coordinates])
        if coords
          blob = @workspace.logo_original.blob
          blob.update!(metadata: blob.metadata.merge("crop" => coords))
        end
      end

      # Handle nested form params (branding form)
      if params.dig(:workspace, :logo).present?
        @workspace.logo.attach(params[:workspace][:logo])
      end

      # Crop save (logo file present) keeps modal open; hub save (no logo) closes it
      @close_modal = params[:logo].blank?

      if @workspace.update(branding_params)
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to edit_workspace_branding_path(@workspace), notice: t(".success") }
        end
      else
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

    private

    def branding_params
      params.require(:workspace).permit(:primary_color)
    rescue ActionController::ParameterMissing
      {}
    end

    def safe_parse_coordinates(raw)
      return nil if raw.blank?

      parsed = JSON.parse(raw)
      return nil unless parsed.is_a?(Hash)
      return nil unless %w[x y w h].all? { |k| parsed[k].is_a?(Numeric) }

      parsed.slice("x", "y", "w", "h")
    rescue JSON::ParserError
      nil
    end
  end
end
