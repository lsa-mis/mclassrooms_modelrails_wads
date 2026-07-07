require "rails_helper"

# The auth initializer (config/initializers/auth.rb) validates the SSO-only
# posture configuration at boot and raises on invalid values. It already ran
# (cleanly) when the test app booted; here we re-execute it under stubbed
# ENV/config to exercise both raise paths and the happy path — same
# fail-fast precedent as spec/initializers/tenancy_spec.rb and
# webauthn_config_spec.rb.
RSpec.describe "config/initializers/auth.rb" do
  INITIALIZER_PATH = Rails.root.join("config/initializers/auth.rb")

  def run_initializer
    load INITIALIZER_PATH
  end

  before do
    allow(ENV).to receive(:key?).and_call_original
    allow(ENV).to receive(:[]).and_call_original
  end

  describe "AUTH_SSO_ONLY validation" do
    it "raises with a clear message on a value that is neither 'true' nor 'false'" do
      allow(ENV).to receive(:key?).with("AUTH_SSO_ONLY").and_return(true)
      allow(ENV).to receive(:[]).with("AUTH_SSO_ONLY").and_return("maybe")

      expect { run_initializer }.to raise_error(
        RuntimeError, /Invalid AUTH_SSO_ONLY: "maybe"\. Must be one of: true, false/
      )
    end

    it "accepts 'true'" do
      allow(ENV).to receive(:key?).with("AUTH_SSO_ONLY").and_return(true)
      allow(ENV).to receive(:[]).with("AUTH_SSO_ONLY").and_return("true")

      expect { run_initializer }.not_to raise_error
    end

    it "accepts 'false'" do
      allow(ENV).to receive(:key?).with("AUTH_SSO_ONLY").and_return(true)
      allow(ENV).to receive(:[]).with("AUTH_SSO_ONLY").and_return("false")

      expect { run_initializer }.not_to raise_error
    end

    it "accepts the var being unset (env-defaulted)" do
      allow(ENV).to receive(:key?).with("AUTH_SSO_ONLY").and_return(false)

      expect { run_initializer }.not_to raise_error
    end
  end

  describe "ALLOWED_GOOGLE_DOMAINS validation" do
    it "raises on an email-shaped entry (full address pasted instead of a bare domain)" do
      allow(Rails.configuration.x.auth).to receive(:allowed_google_domains)
        .and_return([ "user@umich.edu" ])

      expect { run_initializer }.to raise_error(
        RuntimeError, /Invalid ALLOWED_GOOGLE_DOMAINS entries.*user@umich\.edu/
      )
    end

    it "raises on an entry containing internal whitespace" do
      allow(Rails.configuration.x.auth).to receive(:allowed_google_domains)
        .and_return([ "umich .edu" ])

      expect { run_initializer }.to raise_error(RuntimeError, /Invalid ALLOWED_GOOGLE_DOMAINS/)
    end

    it "accepts bare domains" do
      allow(Rails.configuration.x.auth).to receive(:allowed_google_domains)
        .and_return(%w[umich.edu lsa.umich.edu])

      expect { run_initializer }.not_to raise_error
    end

    it "accepts an empty allowlist (the dev-friendly default)" do
      allow(Rails.configuration.x.auth).to receive(:allowed_google_domains).and_return([])

      expect { run_initializer }.not_to raise_error
    end
  end
end
