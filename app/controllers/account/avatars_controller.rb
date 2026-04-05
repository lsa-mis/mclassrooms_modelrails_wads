module Account
  class AvatarsController < ApplicationController
    def update
      file = params.dig(:user, :avatar)

      if file.present?
        Current.user.avatar.attach(file)
        Current.user.avatar_source = "upload"

        if Current.user.save
          redirect_to edit_account_profile_path, notice: t(".success")
        else
          Current.user.avatar.purge
          redirect_to edit_account_profile_path, alert: Current.user.errors.full_messages.to_sentence
        end
      elsif params.dig(:user, :avatar_source).present?
        if Current.user.update(avatar_source: params[:user][:avatar_source])
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
