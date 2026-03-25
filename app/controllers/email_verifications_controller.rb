class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access

  def show
    authentication = Authentication.find_by(verification_token: params[:token])

    if authentication.nil?
      redirect_to root_path, alert: t(".invalid_token")
    elsif authentication.verification_token_expired?
      redirect_to root_path, alert: t(".expired_token")
    else
      authentication.verify!
      redirect_to root_path, notice: t(".success")
    end
  end
end
