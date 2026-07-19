class FeedbackMailer < ApplicationMailer
  # Fallback delivery when TeamDynamix isn't configured (or a TDX submission
  # errors): email the directory's admins so feedback is never lost before TDX
  # creds are provisioned. Feedback::Submit is the only caller; it passes the
  # recipient list and the submitted fields.
  def submission(recipients:, message:, email:, category: nil, url: nil, user_agent: nil, additional_info: nil)
    @message = message
    @email = email
    @category = category
    @url = url
    @user_agent = user_agent
    @additional_info = additional_info

    mail(to: recipients, reply_to: email,
      subject: t("feedback.mailer.submission.subject", app_name: t("application.name")))
  end
end
