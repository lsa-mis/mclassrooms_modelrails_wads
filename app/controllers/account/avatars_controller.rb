module Account
  class AvatarsController < ApplicationController
    def update
      file = params.dig(:user, :avatar)
      if file.present?
        Current.user.avatar.attach(file)
        redirect_to edit_account_profile_path, notice: t(".success")
      else
        redirect_to edit_account_profile_path, alert: t(".no_file")
      end
    end

    def destroy
      Current.user.avatar.purge
      redirect_to edit_account_profile_path, notice: t(".removed")
    end
  end
end
