class ReauthenticationMailer < ApplicationMailer
  def code(user, code)
    @user = user
    @code = code
    @expiry_minutes = (ReauthenticationChallenge::EXPIRY / 60).to_i

    mail(
      to: user.email_address,
      subject: t("reauthentication_mailer.code.subject")
    )
  end
end
