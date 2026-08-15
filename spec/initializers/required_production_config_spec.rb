require "rails_helper"

# The initializer defines RequiredProductionConfig and calls .check! only when
# booting a real production process, so loading it here is side-effect free.
load Rails.root.join("config/initializers/required_production_config.rb").to_s unless defined?(RequiredProductionConfig)

RSpec.describe RequiredProductionConfig do
  describe ".check!" do
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
      expect { described_class.check!({ "RAILS_HOST" => "app.humbledaisy.com" }) }
        .not_to raise_error
    end

    it "accepts a hostname that merely contains the word example" do
      expect { described_class.check!({ "RAILS_HOST" => "goodexample.io" }) }
        .not_to raise_error
    end

    it "names the fix and the opt-out in the message" do
      described_class.check!({})
      raise "expected check! to raise"
    rescue RuntimeError => e
      expect(e.message).to include("env.clear")
      expect(e.message).to include("git rm config/initializers/required_production_config.rb")
      expect(e.message).to include("/docs/developer/deployment")
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
end
