class MagicLinkMailer < ApplicationMailer
  def sign_in_link(email, token)
    @user = User.find_by(email_address: email)
    @link_url = magic_link_callback_url(token: token)

    mail(
      to: email,
      subject: t("magic_link_mailer.sign_in_link.subject")
    )
  end

  def registration_link(email, token)
    @email = email
    @link_url = magic_link_callback_url(token: token)

    mail(
      to: email,
      subject: t("magic_link_mailer.registration_link.subject")
    )
  end
end
