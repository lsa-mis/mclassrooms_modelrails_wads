# A send that never reached the server retries; one that may have been accepted does not, or it could arrive twice (#1349).
require "net/smtp"

Rails.application.config.after_initialize do
  ActionMailer::MailDeliveryJob.retry_on Net::OpenTimeout, Net::SMTPServerBusy, Errno::ECONNREFUSED,
    wait: :polynomially_longer, attempts: 5
end
