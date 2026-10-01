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

  describe ".delivery_method" do
    it "is smtp by default" do
      expect(described_class.delivery_method({})).to eq(:smtp)
    end

    it "accepts smtp spelled out" do
      expect(described_class.delivery_method("MAIL_DELIVERY" => "smtp")).to eq(:smtp)
    end

    it "refuses a transport it does not ship, naming the variable" do
      expect { described_class.delivery_method("MAIL_DELIVERY" => "postmark") }
        .to raise_error(ArgumentError, /MAIL_DELIVERY.*"postmark"/)
    end
  end

  describe ".unconfigured_reason" do
    it "is nil for a real server" do
      expect(described_class.unconfigured_reason(env)).to be_nil
    end

    it "names an unset address" do
      expect(described_class.unconfigured_reason({})).to eq("unset")
    end

    it "names localhost, which is where Rails mails by default" do
      expect(described_class.unconfigured_reason("SMTP_ADDRESS" => "localhost")).to eq('"localhost"')
      expect(described_class.unconfigured_reason("SMTP_ADDRESS" => "127.0.0.1")).to eq('"127.0.0.1"')
    end

    it "names the rails new and bin/fork placeholders" do
      expect(described_class.unconfigured_reason("SMTP_ADDRESS" => "smtp.example.com")).to eq('"smtp.example.com"')
      expect(described_class.unconfigured_reason("SMTP_ADDRESS" => "mail.my_app.example")).to eq('"mail.my_app.example"')
    end
  end
end
