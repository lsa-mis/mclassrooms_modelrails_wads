module Settings
  # Emails a one-time re-authentication code, then returns to the interstitial
  # (which now shows a code-entry field). Rate-limited so it can't be used to
  # spam a user's inbox.
  class ReauthenticationCodesController < ApplicationController
    # Same reason as ReauthenticationsController: an un-onboarded operator's
    # only factor may be this emailed code.
    skip_onboarding_requirement
    rate_limit to: 5, within: 3.minutes, only: :create,
      by: -> { Current.user&.id || request.remote_ip },
      with: -> { redirect_to new_settings_reauthentication_path, alert: t("settings.reauthentications.rate_limited") }

    def create
      code = ReauthenticationChallenge.issue_for(Current.user)
      ReauthenticationMailer.code(Current.user, code).deliver_later
      session[:reauthentication_code_sent] = true
      redirect_to new_settings_reauthentication_path, notice: t(".sent")
    end
  end
end
