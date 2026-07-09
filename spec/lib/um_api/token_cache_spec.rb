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

    # The fixture's expires_in is 3600, so the buffered expiry is at
    # +3540 (3600 - EARLY_EXPIRY). These two cases straddle that boundary to
    # prove the 60s buffer is actually applied, not just that the token
    # "eventually" refetches: +3500 is still inside the buffer (cached), and
    # +3550 is past the buffer but still BEFORE the token's true 3600s expiry
    # — so a refetch there can ONLY happen if EARLY_EXPIRY is honored. (With
    # EARLY_EXPIRY = 0 the +3550 case would still read the cache and this
    # example would fail — that's the teeth.)
    it "keeps serving the cached token just before the buffered expiry" do
      stub = stub_um_token(scope: "buildings")
      clock = FakeClock.new(Time.utc(2026, 1, 1, 0, 0, 0))
      cache = described_class.new(clock: clock)

      cache.token_for("buildings")
      clock.now += 3500 # inside the 3540s buffered window
      cache.token_for("buildings")

      expect(stub).to have_been_requested.once
    end

    it "refetches past the buffered expiry even before the token's true expiry" do
      stub = stub_um_token(scope: "buildings")
      clock = FakeClock.new(Time.utc(2026, 1, 1, 0, 0, 0))
      cache = described_class.new(clock: clock)

      cache.token_for("buildings")
      clock.now += 3550 # past 3540 (buffered) but before 3600 (true expiry)
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

    # Race on a COLD cache: 10 threads are parked at a gate and released as
    # simultaneously as the scheduler allows, so they all reach #token_for
    # with an empty cache at once. The Mutex must let exactly ONE thread run
    # the fetch-and-cache while the other nine block, then read the cached
    # entry — so the token endpoint is hit EXACTLY once. Without the mutex,
    # several threads would see the empty cache and each fetch, so the count
    # would exceed one. `.once` (never `.at_least_once`) is what gives this
    # teeth; no sleeps — the `ready`/`go` queues are the barrier.
    it "is thread-safe: concurrent cold-cache callers trigger exactly one fetch" do
      stub = stub_um_token(scope: "buildings")
      cache = described_class.new
      ready = Queue.new
      go = Queue.new

      threads = Array.new(10) do
        Thread.new do
          ready << true
          go.pop
          cache.token_for("buildings")
        end
      end

      10.times { ready.pop } # every thread is up and parked at the gate
      10.times { go << :release } # release them together

      results = threads.map(&:value)

      expect(results.uniq).to eq([ "test-um-api-token-abc123" ])
      expect(stub).to have_been_requested.once
    end
  end
end
