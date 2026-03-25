module Account
  class ProfilesController < ApplicationController
    def edit
      @user = Current.user
    end

    def update
      @user = Current.user
      if @user.update(profile_params)
        redirect_to edit_account_profile_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      params.require(:user).permit(:first_name, :last_name, :email_address)
    end
  end
end
