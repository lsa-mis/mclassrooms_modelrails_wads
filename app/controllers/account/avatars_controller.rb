module Account
  class AvatarsController < ApplicationController
    def update
      Current.user.avatar.attach(params[:user][:avatar])
      redirect_to edit_account_profile_path, notice: t(".success")
    end

    def destroy
      Current.user.avatar.purge
      redirect_to edit_account_profile_path, notice: t(".removed")
    end
  end
end
