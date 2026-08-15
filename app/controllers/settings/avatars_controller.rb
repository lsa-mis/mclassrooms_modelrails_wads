module Settings
  class AvatarsController < ApplicationController
    rate_limit to: 20, within: 3.minutes, only: [ :update, :destroy ],
      by: -> { Current.user&.id || request.remote_ip },
      with: -> {
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: error_toast(t("settings.avatars.update.rate_limited")),
                   status: :too_many_requests
          end
          format.html { redirect_to edit_settings_profile_path, alert: t("settings.avatars.update.rate_limited") }
        end
      }

    def hub
      @user = Current.user
      authorize @user, :update?, policy_class: Settings::AvatarPolicy
      identity = @user.identity

      render partial: "shared/identity_picker_hub",
        locals: {
          identity: identity,
          form_url: settings_avatar_path,
          hub_url: hub_settings_avatar_path,
          current_source: identity.resolve_source(params[:source])
        },
        layout: false
    end

    def update
      user = Current.user
      authorize user, policy_class: Settings::AvatarPolicy

      result = user.identity.apply(**identity_update_params)
      # Crop save (file present) keeps the modal open; hub save closes it.
      @close_modal = identity_update_params[:image].blank?

      if result.success?
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to edit_settings_profile_path, notice: t(".success") }
        end
      else
        message = result.error == :source_unavailable ? t("settings.avatars.source_unavailable") : result.error_message
        status = result.error == :source_unavailable ? :forbidden : :unprocessable_content
        respond_to do |format|
          format.turbo_stream { render turbo_stream: error_toast(message), status: status }
          format.html { redirect_to edit_settings_profile_path, alert: message }
        end
      end
    end

    def destroy
      authorize Current.user, policy_class: Settings::AvatarPolicy
      result = Current.user.identity.apply(source: "initials")

      if result.success?
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to edit_settings_profile_path, notice: t(".success") }
        end
      else
        respond_to do |format|
          format.turbo_stream { render turbo_stream: error_toast(result.error_message), status: :unprocessable_content }
          format.html { redirect_to edit_settings_profile_path, alert: result.error_message }
        end
      end
    end

    private

    # Explicit extraction of the identity-picker wire protocol — top-level
    # params, frozen (the JS posts these names for both User and Workspace).
    def identity_update_params
      @identity_update_params ||= {
        image: params[:avatar],
        image_original: params[:avatar_original],
        crop_coordinates: params[:crop_coordinates],
        source: params[:avatar_source],
        color: params[:primary_color]
      }
    end
  end
end
