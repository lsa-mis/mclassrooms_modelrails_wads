class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: :show
  skip_onboarding_requirement

  def new
    @authentication = Current.user&.authentications&.email&.first
  end

  def show
    authentication = Authentication.find_by_token_for(:email_verification, params[:token])

    # Signed tokens can't distinguish "tampered" from "expired" — both surface
    # as a nil lookup, so we show a single combined message.
    if authentication.nil?
      redirect_to root_path, alert: t(".invalid_or_expired")
    else
      authentication.verify!
      redirect_to root_path, notice: t(".success")
    end
  end
end
