class EmailVerificationResendsController < ApplicationController
  skip_onboarding_requirement
  rate_limit to: 5, within: 3.minutes, only: :create,
    with: -> { redirect_to new_email_verification_path, alert: t("email_verification_resends.create.rate_limited") }

  def create
    authentication = Current.user.authentications.email.first

    if authentication&.verified?
      redirect_to root_path, notice: t(".already_verified")
    elsif authentication
      AuthenticationMailer.verification_email(authentication).deliver_later
      redirect_to new_email_verification_path, notice: t(".success")
    else
      redirect_to root_path, alert: t(".no_email_auth")
    end
  end
end
