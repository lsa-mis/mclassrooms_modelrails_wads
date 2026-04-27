module Account
  class AvatarsController < ApplicationController
    include CropCoordinatable

    rate_limit to: 20, within: 3.minutes, only: :update,
      by: -> { Current.user&.id || request.remote_ip },
      with: -> {
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: error_toast(t("account.avatars.update.rate_limited")),
                   status: :too_many_requests
          end
          format.html { redirect_to edit_account_profile_path, alert: t("account.avatars.update.rate_limited") }
        end
      }

    def hub
      @user = Current.user
      authorize @user, :update?, policy_class: Account::AvatarPolicy

      @source = if params[:source].present? && @user.available_avatar_sources.include?(params[:source])
                  params[:source]
      else
                  @user.avatar_source
      end

      is_user = true
      has_image = @user.avatar.attached?
      current_hue = @user.primary_color || 210
      display_url = has_image ? url_for(@user.avatar) : nil
      gravatar_url = @user.gravatar_url(size: 256)

      render partial: "shared/identity_picker_hub",
        locals: {
          model: @user,
          form_url: account_avatar_path,
          hub_url: hub_account_avatar_path,
          current_source: @source,
          has_color_picker: true,
          available_sources: @user.available_avatar_sources,
          is_user: is_user,
          has_image: has_image,
          current_hue: current_hue,
          display_url: display_url,
          gravatar_url: gravatar_url,
          initials: @user.initials,
          hub_title: t("identity_picker.choose_profile_picture")
        },
        layout: false
    end

    def update
      user = Current.user
      authorize user, policy_class: Account::AvatarPolicy

      # Guard: reject upload attempts when upload is not an available source for this user
      if params[:avatar_source] == "upload" && !user.available_avatar_sources.include?("upload")
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.append("toast-cards",
              partial: "shared/toast_card",
              locals: { type: :error, message: t("account.avatars.source_unavailable") }),
                   status: :forbidden
          end
          format.html { redirect_to edit_account_profile_path, alert: t("account.avatars.source_unavailable") }
        end
        return
      end

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
      authorize Current.user, policy_class: Account::AvatarPolicy
      Current.user.avatar.purge
      Current.user.avatar_original.purge if Current.user.avatar_original.attached?
      Current.user.update!(avatar_source: "initials")

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_account_profile_path, notice: t(".success") }
      end
    end
  end
end
