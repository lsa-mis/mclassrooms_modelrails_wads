# Outbound mail is SMTP from ENV, so swapping providers is a change of secrets.
# Postmark and SES recipes: /docs/developer/deployment (Configure outbound mail).
module MailDelivery
  def self.smtp_settings(env = ENV)
    {
      address: env["SMTP_ADDRESS"],
      port: env.fetch("SMTP_PORT", "587").to_i,
      domain: env["SMTP_DOMAIN"].presence || env["RAILS_HOST"],
      user_name: env["SMTP_USERNAME"],
      password: env["SMTP_PASSWORD"],
      authentication: :plain,
      enable_starttls_auto: true
    }
  end
end
