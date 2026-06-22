module Settings
  class PasswordsController < ApplicationController
    def new
      redirect_to edit_settings_password_path if Current.user.has_password?
    end

    def create
      if Current.user.has_password?
        redirect_to edit_settings_password_path, alert: t(".already_has_password")
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

    def edit
      redirect_to new_settings_password_path unless Current.user.has_password?
    end

    def update
      unless Current.user.has_password?
        redirect_to new_settings_password_path
        return
      end

      if Current.user.update(password_params)
        redirect_to settings_connected_accounts_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      Current.user.authentications.email.destroy_all
      Current.user.update_columns(password_digest: nil)
      redirect_to settings_connected_accounts_path, notice: t(".success")
    end

    private

    def password_params
      params.require(:user).permit(:password, :password_confirmation)
    end
  end
end
