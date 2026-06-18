module Settings
  class PasswordsController < ApplicationController
    def new
      if Current.user.authentications.email.exists?
        redirect_to edit_settings_profile_path, notice: t(".already_has_password")
        nil
      end
    end

    def create
      if Current.user.authentications.email.exists?
        redirect_to edit_settings_profile_path, alert: t(".already_has_password")
        return
      end

      if Current.user.update(password_params)
        Current.user.authentications.create!(
          provider: "email",
          uid: Current.user.email_address,
          verified_at: Time.current
        )
        redirect_to settings_connected_accounts_path, notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def password_params
      params.require(:user).permit(:password, :password_confirmation)
    end
  end
end
