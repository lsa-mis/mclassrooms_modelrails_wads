module Account
  class AvatarsController < ApplicationController
    def update
      user = Current.user
      authorize user, policy_class: Account::AvatarPolicy

      # Handle file attachments (from crop save flow)
      if params[:avatar].present?
        user.avatar.attach(params[:avatar])
        user.avatar_source = "upload"
      end

      if params[:avatar_original].present?
        user.avatar_original.attach(params[:avatar_original])
      end

      # Store crop coordinates in original blob metadata
      if params[:crop_coordinates].present? && user.avatar_original.attached?
        coords = safe_parse_coordinates(params[:crop_coordinates])
        if coords
          blob = user.avatar_original.blob
          blob.update!(metadata: blob.metadata.merge("crop" => coords))
        end
      end

      # Handle source + color change (from hub save flow)
      # Skip avatar_source param when a file was uploaded (source already set to "upload")
      if params[:avatar_source].present? && params[:avatar].blank?
        source = params[:avatar_source]
        unless user.available_avatar_sources.include?(source)
          redirect_to edit_account_profile_path, alert: t("account.avatars.source_unavailable")
          return
        end
        user.avatar_source = source

        # Switching away from upload (e.g. removePhoto) — purge blobs immediately
        if source != "upload"
          user.avatar.purge if user.avatar.attached?
          user.avatar_original.purge if user.avatar_original.attached?
        end
      end

      if params[:primary_color].present?
        user.primary_color = params[:primary_color].to_i
      end

      # Crop save (file present) keeps modal open; hub save (no file) closes it
      @close_modal = params[:avatar].blank?

      if user.save
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to edit_account_profile_path, notice: t(".success") }
        end
      else
        user.avatar.purge if params[:avatar].present?
        user.avatar_original.purge if params[:avatar_original].present?

        error_message = user.errors.full_messages.to_sentence

        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.append("toast-cards",
              partial: "shared/toast_card",
              locals: { type: :error, message: error_message }),
                   status: :unprocessable_content
          end
          format.html { redirect_to edit_account_profile_path, alert: error_message }
        end
      end
    end

    def destroy
      Current.user.avatar.purge
      Current.user.avatar_original.purge if Current.user.avatar_original.attached?
      Current.user.update!(avatar_source: "initials")
      redirect_to edit_account_profile_path, notice: t(".success")
    end

    private

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
