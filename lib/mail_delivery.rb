# Outbound mail is SMTP from ENV, so swapping providers is a change of secrets.
# Postmark and SES recipes: /docs/developer/deployment (Configure outbound mail).
module MailDelivery
  # localhost is where Rails mails by default; example.com is the rails new
  # template; .example is what bin/fork substitutes. None can ever deliver.
  PLACEHOLDER = /\A(localhost|127\.0\.0\.1|(.+\.)?example(\.com)?)\z/

  # Only smtp ships. The variable exists so an API transport can join later
  # without renaming anything a deployment already sets.
  TRANSPORTS = { "smtp" => :smtp }.freeze

  def self.delivery_method(env = ENV)
    name = env.fetch("MAIL_DELIVERY", "smtp")
    TRANSPORTS.fetch(name) do
      raise ArgumentError, "MAIL_DELIVERY is #{name.inspect}; this app ships #{TRANSPORTS.keys.join(", ")}"
    end
  end

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

  # nil when mail can leave; otherwise the word for the error message.
  def self.unconfigured_reason(env = ENV)
    address = env["SMTP_ADDRESS"].to_s.strip
    return "unset" if address.empty?

    address.inspect if PLACEHOLDER.match?(address)
  end
end
