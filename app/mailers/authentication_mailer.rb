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

  def email_change_verification(user)
    @user = user
    @verification_url = account_email_confirmation_url(token: user.pending_email_token)

    mail(
      to: user.pending_email,
      subject: t("authentication_mailer.email_change_verification.subject")
    )
  end

  def email_change_notification(user)
    @user = user
    @new_email = user.pending_email

    mail(
      to: user.email_address,
      subject: t("authentication_mailer.email_change_notification.subject")
    )
  end

  def link_verification_email(authentication)
    @user = authentication.user
    @authentication = authentication
    @verify_url = verify_account_connected_accounts_url(token: authentication.verification_token)
    @app_name = I18n.t("application.name")
    @provider_name = authentication.provider.titleize

    mail(
      to: authentication.email,
      subject: I18n.t("authentication_mailer.link_verification_email.subject",
                      provider: @provider_name, app_name: @app_name)
    )
  end
end
