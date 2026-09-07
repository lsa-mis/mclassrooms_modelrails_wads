class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: [ :show, :create ]
  skip_onboarding_requirement

  def new
    @authentication = Current.user&.authentications&.email&.first
  end

  # Confirmation only: a mail scanner or prefetcher doing a bare GET must not
  # verify anything (#950). The POST below is what verifies.
  def show
    @authentication = Authentication.find_by_token_for(:email_verification, params[:token])

    # Signed tokens can't distinguish "tampered" from "expired" — both surface
    # as a nil lookup, so we show a single combined message.
    return redirect_to root_path, alert: t(".invalid_or_expired") if @authentication.nil?

    @token = params[:token]
  end

  def create
    authentication = Authentication.find_by_token_for(:email_verification, params[:token])

    if authentication&.verify!
      redirect_to after_authentication_url, notice: t(".success")
    else
      redirect_to root_path, alert: t("email_verifications.show.invalid_or_expired")
    end
  end
end
