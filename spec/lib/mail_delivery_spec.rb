require "rails_helper"
require "mail_delivery"

# Outbound mail is SMTP from ENV, so a provider is a change of secrets (#1318).
RSpec.describe MailDelivery do
  let(:env) do
    { "RAILS_HOST" => "app.humbledaisy.com", "SMTP_ADDRESS" => "smtp.postmarkapp.com",
      "SMTP_USERNAME" => "token", "SMTP_PASSWORD" => "token" }
  end

  describe ".smtp_settings" do
    it "reads the provider from the environment" do
      expect(described_class.smtp_settings(env)).to include(
        address: "smtp.postmarkapp.com", user_name: "token", password: "token", authentication: :plain
      )
    end

    it "defaults the port to submission and the HELO domain to RAILS_HOST" do
      expect(described_class.smtp_settings(env)).to include(port: 587, domain: "app.humbledaisy.com")
    end

    it "takes an explicit port and domain" do
      settings = described_class.smtp_settings(env.merge("SMTP_PORT" => "2525", "SMTP_DOMAIN" => "mail.humbledaisy.com"))

      expect(settings).to include(port: 2525, domain: "mail.humbledaisy.com")
    end
  end
end
