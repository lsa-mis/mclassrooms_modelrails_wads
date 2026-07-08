require "rails_helper"

# MiClassrooms Phase 0 Task 8: pins the route-drawing predicate for the
# non-production test login (config/routes/app.rb reads
# AuthConfig.test_login_enabled? to decide whether GET /test_login is drawn
# at all). Exercised directly here — rather than by reloading routes — per
# the task brief: reloading routes per example is exactly the kind of
# global-state-mutating test the extraction is meant to avoid.
RSpec.describe AuthConfig do
  around do |example|
    original_token = ENV["TEST_LOGIN_TOKEN"]
    example.run
    original_token.nil? ? ENV.delete("TEST_LOGIN_TOKEN") : ENV["TEST_LOGIN_TOKEN"] = original_token
  end

  describe ".test_login_enabled?" do
    it "is false in production even when a token is configured" do
      ENV["TEST_LOGIN_TOKEN"] = "s3cr3t"
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      expect(described_class.test_login_enabled?).to be(false)
    end

    it "is false outside production when no token is configured" do
      ENV.delete("TEST_LOGIN_TOKEN")
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))

      expect(described_class.test_login_enabled?).to be(false)
    end

    it "is false outside production when the configured token is blank" do
      ENV["TEST_LOGIN_TOKEN"] = ""
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

      expect(described_class.test_login_enabled?).to be(false)
    end

    it "is true outside production when a token is configured" do
      ENV["TEST_LOGIN_TOKEN"] = "s3cr3t"
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

      expect(described_class.test_login_enabled?).to be(true)
    end
  end

  describe ".test_login_admin?" do
    around do |example|
      original = ENV["TEST_LOGIN_ADMIN"]
      example.run
      original.nil? ? ENV.delete("TEST_LOGIN_ADMIN") : ENV["TEST_LOGIN_ADMIN"] = original
    end

    it "is true only for the exact string 'true'" do
      ENV["TEST_LOGIN_ADMIN"] = "true"
      expect(described_class.test_login_admin?).to be(true)
    end

    it "is false when unset" do
      ENV.delete("TEST_LOGIN_ADMIN")
      expect(described_class.test_login_admin?).to be(false)
    end

    it "is false for any other value" do
      ENV["TEST_LOGIN_ADMIN"] = "yes"
      expect(described_class.test_login_admin?).to be(false)
    end
  end
end
