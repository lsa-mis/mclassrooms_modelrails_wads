class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV["MAIL_FROM"].presence || Rails.application.credentials.dig(:mailer, :from) || "noreply@#{default_host}" }
  layout "mailer"

  private

  def default_host
    Rails.application.config.action_mailer.default_url_options&.fetch(:host, "example.com")
  end
end
