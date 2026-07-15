require "rails_helper"

RSpec.describe "Content Security Policy" do
  let(:policy) { Rails.application.config.content_security_policy }
  let(:form_action) { policy.directives["form-action"] || [] }

  # When you add a new OAuth provider to OauthHelper::PROVIDER_CONFIG,
  # add the provider's consent-screen host to the hash below AND to
  # config/initializers/content_security_policy.rb's form_action directive.
  EXPECTED_OAUTH_HOSTS_BY_PROVIDER = {
    google_oauth2: "https://accounts.google.com",
    github:        "https://github.com",
    okta:          "https://*.okta.com"
  }.freeze

  it "allows form-action to every configured OAuth provider host" do
    OauthHelper::PROVIDER_CONFIG.each_key do |provider|
      expected_host = EXPECTED_OAUTH_HOSTS_BY_PROVIDER.fetch(provider) do
        raise <<~MSG.strip
          Missing CSP form-action host for OAuth provider :#{provider}.
          Add it to EXPECTED_OAUTH_HOSTS_BY_PROVIDER in this spec file:
            #{__FILE__}
          AND to config/initializers/content_security_policy.rb's
          policy.form_action call.
        MSG
      end
      expect(form_action).to include(expected_host),
        "CSP form-action must include #{expected_host} for OAuth provider #{provider}"
    end
  end

  it "always includes :self in form-action" do
    expect(form_action).to include(:self).or include("'self'")
  end

  describe "report-only mode" do
    # PR #120 deliberately enforced CSP in test (config/environments/test.rb
    # sets report_only = false) specifically so bugs like the blank-nonce one
    # below would fail the suite instead of shipping silently. But this
    # initializer used to ALSO set content_security_policy_report_only, keyed
    # on Rails.env.test? — loaded AFTER config/environments/test.rb in Rails'
    # boot order, so it silently reverted PR #120's fix the whole time. Full
    # system+request suite verified clean with enforcement actually live
    # (1578 examples, 0 failures) before this was restored.
    it "is enforced (not report-only) in test, matching dev/prod" do
      expect(Rails.application.config.content_security_policy_report_only).to be(false)
    end
  end

  describe "nonce generator" do
    let(:nonce_generator) { Rails.application.config.content_security_policy_nonce_generator }

    # The bug this guards against: on a visitor's FIRST request there is no
    # session yet, so a generator that reads request.session.id directly
    # returns "" — Rails then emits `script-src ... 'nonce-'`, an invalid CSP
    # source the browser ignores, blocking every inline script (the importmap
    # bootstrap + `import "application"`). Stimulus never boots for first-time
    # visitors. A unit test on the generator is still the most direct guard
    # (a request spec would only catch it now that CSP is actually enforced
    # in test — see "report-only mode" above; belt and suspenders).
    it "never returns a blank nonce, even when the session has no id yet" do
      request_without_session = instance_double(ActionDispatch::Request, session: instance_double(ActionDispatch::Request::Session, id: nil))

      nonce = nonce_generator.call(request_without_session)

      expect(nonce).to be_present
    end

    it "returns the session id (stable per session) when a session exists" do
      request_with_session = instance_double(ActionDispatch::Request, session: instance_double(ActionDispatch::Request::Session, id: "abc123"))

      nonce = nonce_generator.call(request_with_session)

      expect(nonce).to eq("abc123")
    end
  end
end

# Regression: the nonce generator used `request.session.id.to_s`, which is
# BLANK on a visitor's FIRST (sessionless) request — exactly when the cookie
# consent banner appears. A blank nonce renders as `'nonce-'`, an invalid CSP
# source browsers ignore, which then blocks EVERY inline script (the importmap
# bootstrap + the module entry). Stimulus never boots, so the banner's buttons
# (and all other controllers) do nothing. This was invisible to the suite
# because CSP runs report-only in test.
RSpec.describe "CSP nonce generator" do
  let(:generator) { Rails.application.config.content_security_policy_nonce_generator }

  it "returns a non-blank nonce even when the request has no session id yet" do
    request = double("request", session: double("session", id: nil))

    expect(generator.call(request)).to be_present
  end

  it "reuses the session id as the nonce once a session exists" do
    request = double("request", session: double("session", id: "sess-abc123"))

    expect(generator.call(request)).to eq("sess-abc123")
  end
end
