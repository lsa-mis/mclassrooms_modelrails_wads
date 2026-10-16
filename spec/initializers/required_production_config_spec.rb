require "rails_helper"

# The initializer defines RequiredProductionConfig and calls .check! only when
# booting a real production process, so loading it here is side-effect free.
load Rails.root.join("config/initializers/required_production_config.rb").to_s unless defined?(RequiredProductionConfig)

RSpec.describe RequiredProductionConfig do
  describe ".check!" do
    let(:mail) { { "SMTP_ADDRESS" => "smtp.postmarkapp.com", "SMTP_USERNAME" => "token", "SMTP_PASSWORD" => "token" } }

    it "raises when RAILS_HOST is unset" do
      expect { described_class.check!({}) }
        .to raise_error(RuntimeError, /RAILS_HOST is unset/)
    end

    it "raises when RAILS_HOST is blank" do
      expect { described_class.check!({ "RAILS_HOST" => "  " }) }
        .to raise_error(RuntimeError, /RAILS_HOST is unset/)
    end

    it "raises on the Rails default placeholder example.com" do
      expect { described_class.check!({ "RAILS_HOST" => "example.com" }) }
        .to raise_error(RuntimeError, /"example\.com"/)
    end

    it "raises on a bin/fork .example placeholder" do
      expect { described_class.check!({ "RAILS_HOST" => "my_app.example" }) }
        .to raise_error(RuntimeError, /"my_app\.example"/)
    end

    it "raises on the .env.example sample value app.example.com" do
      expect { described_class.check!({ "RAILS_HOST" => "app.example.com" }) }
        .to raise_error(RuntimeError, /preflight failed/)
    end

    it "accepts a real hostname" do
      expect { described_class.check!({ "RAILS_HOST" => "app.humbledaisy.com", **mail }) }
        .not_to raise_error
    end

    it "accepts a hostname that merely contains the word example" do
      expect { described_class.check!({ "RAILS_HOST" => "goodexample.io", **mail }) }
        .not_to raise_error
    end

    # Sign-in is an email; a box that mails localhost:25 boots healthy and nobody can sign in (#1318).
    describe "outbound mail" do
      let(:host) { { "RAILS_HOST" => "app.humbledaisy.com" } }

      it "raises when SMTP_ADDRESS is unset" do
        expect { described_class.check!(host) }
          .to raise_error(RuntimeError, /SMTP_ADDRESS is unset/)
      end

      it "raises on localhost, where Rails mails by default" do
        expect { described_class.check!(host.merge("SMTP_ADDRESS" => "localhost")) }
          .to raise_error(RuntimeError, /"localhost"/)
        expect { described_class.check!(host.merge("SMTP_ADDRESS" => "127.0.0.1")) }
          .to raise_error(RuntimeError, /"127\.0\.0\.1"/)
      end

      it "raises on the rails new and bin/fork placeholders" do
        expect { described_class.check!(host.merge("SMTP_ADDRESS" => "smtp.example.com")) }
          .to raise_error(RuntimeError, /"smtp\.example\.com"/)
        expect { described_class.check!(host.merge("SMTP_ADDRESS" => "mail.my_app.example")) }
          .to raise_error(RuntimeError, /"mail\.my_app\.example"/)
      end

      it "raises when the address is real but a credential is blank, since every send would be refused" do
        expect { described_class.check!(host.merge(mail, "SMTP_PASSWORD" => " ")) }
          .to raise_error(RuntimeError, /SMTP_PASSWORD is unset/)
        expect { described_class.check!(host.merge(mail.except("SMTP_USERNAME", "SMTP_PASSWORD"))) }
          .to raise_error(RuntimeError, /SMTP_USERNAME and SMTP_PASSWORD are unset/)
      end

      it "names the fix and the doc in the message" do
        described_class.check!(host)
        raise "expected check! to raise"
      rescue RuntimeError => e
        expect(e.message).to include("SMTP_ADDRESS")
        expect(e.message).to include("env.secret")
        expect(e.message).to include("/docs/developer/deployment")
      end
    end

    it "names the fix and the opt-out in the message" do
      described_class.check!({})
      raise "expected check! to raise"
    rescue RuntimeError => e
      expect(e.message).to include("env.clear")
      expect(e.message).to include("git rm config/initializers/required_production_config.rb")
      expect(e.message).to include("/docs/developer/deployment")
    end

    # Personal data is encrypted at rest (#902); without keys the app boots,
    # /up reports healthy, and the first user read raises.
    describe "Active Record encryption keys" do
      let(:host) { { "RAILS_HOST" => "app.humbledaisy.com", **mail } }
      let(:keys) { { primary_key: "p", deterministic_key: "d", key_derivation_salt: "s" } }

      it "raises when neither credentials nor config carry the keys" do
        expect { described_class.check!(host, {}, {}) }
          .to raise_error(RuntimeError, /active_record_encryption/)
      end

      it "names the missing key" do
        credentials = { active_record_encryption: keys.except(:deterministic_key) }

        expect { described_class.check!(host, credentials, {}) }
          .to raise_error(RuntimeError, /deterministic_key/)
      end

      it "accepts keys from the credentials" do
        expect { described_class.check!(host, { active_record_encryption: keys }, {}) }
          .not_to raise_error
      end

      it "accepts keys from the encryption config (the environment-variable path)" do
        expect { described_class.check!(host, {}, keys) }
          .not_to raise_error
      end

      it "names the fix in the message" do
        described_class.check!(host, {}, {})
        raise "expected check! to raise"
      rescue RuntimeError => e
        expect(e.message).to include("db:encryption:init")
        expect(e.message).to include("credentials:edit --environment production")
        expect(e.message).to include("/docs/developer/forking")
      end
    end
  end

  describe "boot wiring" do
    let(:source) { Rails.root.join("config/initializers/required_production_config.rb").read }

    it "fires only for real production boots, sparing build-time asset precompile" do
      wiring = source.lines.last
      expect(wiring).to include("Rails.env.production?")
      expect(wiring).to include('ENV["SECRET_KEY_BASE_DUMMY"]')
    end
  end
end

# Host authorization is production-only config, so (like the tenancy
# initializer spec) we assert the source of truth rather than booting a
# production process per example.
RSpec.describe "config/environments/production.rb host authorization" do
  let(:source) { Rails.root.join("config/environments/production.rb").read }

  it "derives config.hosts from RAILS_HOST (DNS-rebinding protection on by default)" do
    line = source.lines.find { |l| l.strip.start_with?("config.hosts") }
    expect(line).to include('ENV["RAILS_HOST"]')
  end

  it "excludes /up from host authorization so the Kamal healthcheck cannot be blocked" do
    line = source.lines.find { |l| l.strip.start_with?("config.host_authorization") }
    expect(line).to include('request.path == "/up"')
  end

  it "takes its SMTP settings from MailDelivery, so a provider is a change of secrets" do
    expect(source).to include("config.action_mailer.smtp_settings = MailDelivery.smtp_settings(ENV)")
  end

  it "lets a failed delivery fail its job instead of vanishing" do
    expect(source).to include("config.action_mailer.raise_delivery_errors = true")
  end
end
