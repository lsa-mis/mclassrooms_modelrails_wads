class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.application.credentials.dig(:mailer, :from) || "noreply@#{default_host}" }
  layout "mailer"

  private

  def default_host
    Rails.application.config.action_mailer.default_url_options&.fetch(:host, "example.com")
  end
end
