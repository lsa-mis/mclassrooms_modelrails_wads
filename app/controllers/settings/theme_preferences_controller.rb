module Settings
  class ThemePreferencesController < ApplicationController
    layout "settings"

    def edit
      @preferences = Current.user.preferences!
      authorize @preferences, policy_class: Settings::ThemePreferencesPolicy
    end

    def update
      preferences = Current.user.preferences!
      authorize preferences, policy_class: Settings::ThemePreferencesPolicy
      preferences.update!(theme: params[:theme] || theme_params[:theme])

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_settings_profile_path, notice: t(".success") }
      end
    rescue ArgumentError
      respond_to do |format|
        format.html { redirect_to edit_settings_profile_path, alert: t(".invalid_theme") }
      end
    end

    private

    def theme_params
      params.require(:user_preferences).permit(:theme)
    end
  end
end
