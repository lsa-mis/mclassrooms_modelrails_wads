require "rails_helper"

RSpec.describe "Content Security Policy" do
  let(:policy) { Rails.application.config.content_security_policy }
  let(:form_action) { policy.directives["form-action"] || [] }

  # DOUBLE-ENTRY cross-check (#312): form_action is DERIVED from the provider
  # registry (config/initializers/0_oauth_provider_registry.rb), so the wiring
  # can't be forgotten — this literal hash independently pins the VALUES, so a
  # wrong host in the registry can't ship either. When you add or swap a
  # provider, update the registry and this hash; the failure below is the
  # reminder, and it fires at spec time instead of as a silent browser-side
  # CSP block on the consent redirect (undebuggable from the symptom).
  expected_oauth_hosts_by_provider = {
    google_oauth2: "https://accounts.google.com",
    github:        "https://github.com",
    okta:          "https://*.okta.com"
  }.freeze

  it "allows form-action to every configured OAuth provider host" do
    OauthHelper::PROVIDER_CONFIG.each_key do |provider|
      expected_host = expected_oauth_hosts_by_provider.fetch(provider) do
        raise <<~MSG.strip
          Missing CSP form-action cross-check for OAuth provider :#{provider}.
          The registry (config/initializers/0_oauth_provider_registry.rb)
          already feeds form_action; add the expected host to
          expected_oauth_hosts_by_provider in this spec file so the VALUE is
          independently pinned:
            #{__FILE__}
        MSG
      end
      expect(form_action).to include(expected_host),
        "CSP form-action must include #{expected_host} for OAuth provider #{provider}"
    end
  end

  it "derives form-action from the registry — exactly :self plus every registered host, nothing hand-added" do
    registry_hosts = Rails.application.config.x.oauth_providers.values.map { |p| p.fetch(:form_action_host) }

    expect(form_action).to match_array([ "'self'", *registry_hosts ]),
      "form_action must be exactly 'self' + the registry's form_action_hosts. " \
      "A host present here but not in the registry was hand-added to the " \
      "initializer (put it in the registry); a registry host missing here " \
      "means the derivation broke."
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

  # SEC-6 invariant: outside development, script-src carries NO remote host.
  # The test env evaluates the same non-development branch production does
  # (the jsdelivr allowance is gated on Rails.env.development? — mirroring
  # the dev-only chart.js importmap pin), so this assertion holds the
  # production posture: a CDN script pin can't silently reopen the door.
  describe "script-src (SEC-6)" do
    it "contains no remote host outside development" do
      script_src = policy.directives["script-src"] || []
      remote = script_src.grep(%r{\Ahttps?://})
      expect(remote).to be_empty,
        "script-src must stay 'self' outside development; found: #{remote.inspect}. " \
        "Vendor the package (see config/importmap.rb's cropperjs comment) instead of allowlisting a CDN."
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
