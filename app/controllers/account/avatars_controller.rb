module Account
  class AvatarsController < ApplicationController
    def update
      user = Current.user

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
        coords = JSON.parse(params[:crop_coordinates])
        blob = user.avatar_original.blob
        blob.update!(metadata: blob.metadata.merge("crop" => coords))
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
      end

      if params[:primary_color].present?
        user.primary_color = params[:primary_color].to_i
      end

      if user.save
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to edit_account_profile_path, notice: t(".success") }
        end
      else
        user.avatar.purge if params[:avatar].present?
        redirect_to edit_account_profile_path, alert: user.errors.full_messages.to_sentence
      end
    end

    def destroy
      Current.user.avatar.purge
      Current.user.avatar_original.purge if Current.user.avatar_original.attached?
      Current.user.update!(avatar_source: "initials")
      redirect_to edit_account_profile_path, notice: t(".success")
    end
  end
end
