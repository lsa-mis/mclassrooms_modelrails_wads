class EmailVerificationResendsController < ApplicationController
  def create
    authentication = Current.user.authentications.email.first

    if authentication&.verified?
      redirect_to root_path, notice: t(".already_verified")
    elsif authentication
      authentication.generate_verification_token!
      AuthenticationMailer.verification_email(authentication).deliver_later
      redirect_to root_path, notice: t(".success")
    else
      redirect_to root_path, alert: t(".no_email_auth")
    end
  end
end
