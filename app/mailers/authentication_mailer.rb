class AuthenticationMailer < ApplicationMailer
  def verification_email(authentication)
    @authentication = authentication
    @user = authentication.user
    @verification_url = email_verification_url(token: authentication.verification_token)

    mail(
      to: @user.email_address,
      subject: t("authentication_mailer.verification_email.subject")
    )
  end

  def password_reset_email(user)
    @user = user
    @reset_url = edit_password_url(token: user.password_reset_token)

    mail(
      to: @user.email_address,
      subject: t("authentication_mailer.password_reset_email.subject")
    )
  end
end
