module Account
  class ThemePreferencesController < ApplicationController
    def update
      preferences = Current.user.preferences || Current.user.create_preferences!
      preferences.update!(theme_params)

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_account_profile_path, notice: t(".success") }
      end
    end

    private

    def theme_params
      params.require(:user_preferences).permit(:theme)
    end
  end
end
