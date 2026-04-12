module Account
  class AvatarsController < ApplicationController
    def update
      if params[:avatar].present?
        Current.user.avatar.attach(params[:avatar])
        Current.user.avatar_source = "upload"

        if Current.user.save
          redirect_to edit_account_profile_path, notice: t(".success")
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
