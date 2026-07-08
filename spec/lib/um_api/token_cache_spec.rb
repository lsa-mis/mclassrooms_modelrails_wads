require "rails_helper"

# Task 3 of planning/plans/phase-2-ingestion.md: UmApi::TokenCache caches a
# per-scope OAuth2 client-credentials bearer token with a 60s early-expiry
# buffer (roadmap Lib section) so sync services (Tasks 6+) don't hit the
# token endpoint on every request. Every example points UM_API_TOKEN_URL at
# spec/support/um_api_stubs.rb's DEFAULT_TOKEN_URL, since TokenCache#fetch
# reads ENV.fetch("UM_API_TOKEN_URL") with no fallback — see the `around`
# block, which follows the same save/restore-ENV pattern as auth_config_spec.
#
# A minimal FakeClock (responds to #now, mutable) stands in for the
# `clock:` constructor arg so expiry can be advanced deterministically —
# no example in this file sleeps or waits on real time.
class FakeClock
  attr_accessor :now

  def initialize(now) = @now = now
end

RSpec.describe UmApi::TokenCache do
  around do |example|
    original_url = ENV["UM_API_TOKEN_URL"]
    original_id = ENV["UM_API_CLIENT_ID"]
    original_secret = ENV["UM_API_CLIENT_SECRET"]
    ENV["UM_API_TOKEN_URL"] = UmApiStubs::DEFAULT_TOKEN_URL
    ENV["UM_API_CLIENT_ID"] = "test-client"
    ENV["UM_API_CLIENT_SECRET"] = "test-secret"

    example.run

    original_url.nil? ? ENV.delete("UM_API_TOKEN_URL") : ENV["UM_API_TOKEN_URL"] = original_url
    original_id.nil? ? ENV.delete("UM_API_CLIENT_ID") : ENV["UM_API_CLIENT_ID"] = original_id
    original_secret.nil? ? ENV.delete("UM_API_CLIENT_SECRET") : ENV["UM_API_CLIENT_SECRET"] = original_secret
  end

  describe "#token_for" do
    it "fetches and returns the bearer token for the given scope" do
      stub_um_token(scope: "buildings")

      token = described_class.new.token_for("buildings")

      expect(token).to eq("test-um-api-token-abc123")
    end

    it "does not make a second HTTP call for a second request within the TTL" do
      stub = stub_um_token(scope: "buildings")
      cache = described_class.new

      cache.token_for("buildings")
      cache.token_for("buildings")

      expect(stub).to have_been_requested.once
    end

    it "refetches once the injected clock passes the cached expiry" do
      stub = stub_um_token(scope: "buildings")
      clock = FakeClock.new(Time.utc(2026, 1, 1, 0, 0, 0))
      cache = described_class.new(clock: clock)

      cache.token_for("buildings")
      clock.now += 3600 # fixture's expires_in, past the 60s early-expiry buffer
      cache.token_for("buildings")

      expect(stub).to have_been_requested.twice
    end

    it "caches distinct scopes independently" do
      buildings_stub = stub_um_token(scope: "buildings")
      classrooms_stub = stub_um_token(scope: "classrooms")
      cache = described_class.new

      cache.token_for("buildings")
      cache.token_for("classrooms")
      cache.token_for("buildings")
      cache.token_for("classrooms")

      expect(buildings_stub).to have_been_requested.once
      expect(classrooms_stub).to have_been_requested.once
    end

    it "raises UmApi::Unauthorized when the token endpoint returns 401" do
      stub_request(:post, UmApiStubs::DEFAULT_TOKEN_URL)
        .with(body: hash_including(grant_type: "client_credentials", scope: "buildings"))
        .to_return(status: 401, body: "")

      expect { described_class.new.token_for("buildings") }.to raise_error(UmApi::Unauthorized)
    end

    it "raises UmApi::Unauthorized when the token endpoint returns 403" do
      stub_request(:post, UmApiStubs::DEFAULT_TOKEN_URL)
        .with(body: hash_including(grant_type: "client_credentials", scope: "department"))
        .to_return(status: 403, body: "")

      expect { described_class.new.token_for("department") }.to raise_error(UmApi::Unauthorized)
    end

    it "is thread-safe: concurrent callers for the same scope only trigger one fetch" do
      stub = stub_um_token(scope: "buildings")
      cache = described_class.new

      threads = Array.new(10) { Thread.new { cache.token_for("buildings") } }
      results = threads.map(&:value)

      expect(results.uniq).to eq([ "test-um-api-token-abc123" ])
      expect(stub).to have_been_requested.at_least_once
    end
  end
end
