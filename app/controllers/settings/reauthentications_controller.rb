module Settings
  # "Confirm it's you" before a sensitive account change. Verifies whatever
  # factor the user has — password or an emailed code here; passkeys go through
  # Passkeys::ReauthenticationsController. Success stamps the current session's
  # reauthenticated_at and returns to the page the user came from.
  class ReauthenticationsController < ApplicationController
    layout "settings"

    rate_limit to: 10, within: 3.minutes, only: :create,
      by: -> { Current.user&.id || request.remote_ip },
      with: -> { redirect_to new_settings_reauthentication_path, alert: t("settings.reauthentications.rate_limited") }

    def new
      @factors = Current.user.available_reauth_factors
      @code_sent = session[:reauthentication_code_sent].present?
    end

    def create
      if params[:password].present?
        verify_password
      elsif params[:code].present?
        verify_code
      else
        redirect_to new_settings_reauthentication_path, alert: t(".no_factor")
      end
    end

    private

    def verify_password
      if Current.user.has_password? && Current.user.authenticate(params[:password])
        succeed
      else
        redirect_to new_settings_reauthentication_path,
                    alert: t("settings.reauthentications.create.wrong_password")
      end
    end

    def verify_code
      if ReauthenticationChallenge.consume(user: Current.user, code: params[:code])
        session.delete(:reauthentication_code_sent)
        succeed
      else
        redirect_to new_settings_reauthentication_path,
                    alert: t("settings.reauthentications.create.wrong_code")
      end
    end

    def succeed
      Current.session.confirm_reauthentication!
      redirect_to reauthentication_return_to
    end
  end
end
