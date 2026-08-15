module Settings
  class EmailConfirmationsController < ApplicationController
    def show
      if Users::EmailChange.new(Current.user).confirm!(params[:token])
        redirect_to edit_settings_profile_path, notice: t(".success")
      else
        redirect_to edit_settings_profile_path, alert: t(".invalid_or_expired")
      end
    end

    def destroy
      Users::EmailChange.new(Current.user).cancel!
      redirect_to edit_settings_profile_path, notice: t(".cancelled")
    end
  end
end
