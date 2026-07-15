require "rails_helper"

RSpec.describe "Content Security Policy", type: :request do
  it "emits a non-empty script-src nonce on a fresh, unauthenticated GET" do
    get "/session/new"

    csp = response.headers["Content-Security-Policy"]
    expect(csp).to be_present

    script_src = csp.split(";").map(&:strip).find { |directive| directive.start_with?("script-src") }
    expect(script_src).to be_present

    nonce = script_src[/'nonce-([^']*)'/, 1]
    expect(nonce).to be_present,
      "expected a non-empty CSP nonce on script-src, got directive: #{script_src.inspect}"
  end
end
