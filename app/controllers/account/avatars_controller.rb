module Account
  class AvatarsController < ApplicationController
    def crop
      unless Current.user.avatar.attached?
        redirect_to edit_account_profile_path, alert: t("image_crop.no_image")
        nil
      end
    end

    def save_crop
      attachment = ActiveStorage::Attachment.find_by(
        record_type: "User",
        record_id: Current.user.id,
        name: "avatar"
      )

      unless attachment
        redirect_to edit_account_profile_path, alert: t("image_crop.no_image")
        return
      end

      crop_params = params.require(:crop).permit(:x, :y, :w, :h).transform_values(&:to_i)
      blob = ActiveStorage::Blob.find(attachment.blob_id)
      blob.update!(metadata: blob.metadata.merge("crop" => crop_params.to_h))

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_account_profile_path, notice: t(".success") }
      end
    end

    def update
      file = params[:avatar]

      if file.present?
        Current.user.avatar.attach(file)
        Current.user.avatar_source = "upload"

        if Current.user.save
          respond_to do |format|
            format.turbo_stream
            format.html { redirect_to crop_account_avatar_path }
          end
        else
          Current.user.avatar.purge
          redirect_to edit_account_profile_path, alert: Current.user.errors.full_messages.to_sentence
        end
      elsif params[:avatar_source].present?
        source = params[:avatar_source]
        unless Current.user.available_avatar_sources.include?(source)
          redirect_to edit_account_profile_path, alert: t("account.avatars.source_unavailable")
          return
        end

        if Current.user.update(avatar_source: source)
          redirect_to edit_account_profile_path, notice: t("account.avatars.source_updated")
        else
          redirect_to edit_account_profile_path, alert: Current.user.errors.full_messages.to_sentence
        end
      else
        redirect_to edit_account_profile_path
      end
    end

    def destroy
      Current.user.avatar.purge
      Current.user.update!(avatar_source: "initials")
      redirect_to edit_account_profile_path, notice: t(".success")
    end
  end
end
