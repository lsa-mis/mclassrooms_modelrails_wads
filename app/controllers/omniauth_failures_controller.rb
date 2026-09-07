# Where OmniAuth's on_failure lands (/auth/failure, a path the middleware
# fixes); the page is a redirect back to sign-in with the reason folded
# into one alert.
class OmniauthFailuresController < ApplicationController
  allow_unauthenticated_access

  def show
    redirect_to new_session_path, alert: t("sessions.create.oauth_failure")
  end
end
