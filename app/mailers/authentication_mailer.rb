class AuthenticationMailer < ApplicationMailer
  def verification_email(authentication)
    @authentication = authentication
    @user = authentication.user
    @verification_url = email_verification_url(token: authentication.generate_token_for(:email_verification))

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
    @verification_url = settings_email_confirmation_url(token: user.pending_email_token)

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
    @verify_url = verify_settings_connected_accounts_url(token: authentication.generate_token_for(:email_verification))
    @app_name = t("application.name")
    @provider_name = authentication.display_provider

    mail(
      to: authentication.email,
      subject: t("authentication_mailer.link_verification_email.subject",
                 provider: @provider_name, app_name: @app_name)
    )
  end

  # Defense-in-depth notification: when an OAuth callback finds that the
  # provider+uid pair is already linked to a DIFFERENT user (cross-user
  # collision), email the legitimate owner of that linkage so they know
  # someone else just tried to attach their OAuth identity to a different
  # ModelRails account. The legitimate user's own account is unaffected
  # — this email is purely informational.
  def collision_alert(legitimate_user, provider_display_name)
    @user = legitimate_user
    @provider_name = provider_display_name
    @app_name = t("application.name")
    @connected_accounts_url = settings_connected_accounts_url

    mail(
      to: legitimate_user.email_address,
      subject: t("authentication_mailer.collision_alert.subject",
                 provider: @provider_name, app_name: @app_name)
    )
  end
end
