require "rails_helper"

# Task 5 of planning/plans/phase-2-ingestion.md: UmApi::Client is the single
# HTTP entry point every sync service (Tasks 6+) uses to talk to the U-M
# Facilities gateway (roadmap Lib section). #get_json fetches one URL;
# #fetch_all (sync-fix Task 1) walks a paginated listing endpoint using the
# real `$start_index`/`$count` query params and the real two-level envelope
# shape, stopping once a page comes back shorter than PAGE_SIZE. Every
# request — each #get_json call, and each page inside #fetch_all — runs
# `rate_limiter.throttle!` first and raises a UmApi::Error subclass (see
# app/lib/um_api.rb) on any non-2xx response; #call_count totals HTTP
# requests actually sent.
#
# Every example points UM_API_BASE_URL/UM_API_TOKEN_URL at
# spec/support/um_api_stubs.rb's DEFAULT_BASE_URL/DEFAULT_TOKEN_URL (the
# `around` block, same save/restore-ENV pattern as token_cache_spec.rb),
# since Client#build_uri reads ENV.fetch("UM_API_BASE_URL") with no
# fallback and the default TokenCache reads UM_API_TOKEN_URL the same way.
# Every example uses the REAL UmApi::TokenCache (via stub_um_token) so the
# scope->bearer-token plumbing is exercised end to end, not mocked away.
#
# ThrottleSpy stands in for `rate_limiter:` — it records how many times
# #throttle! was called instead of doing any real throttling, so specs can
# assert "throttle! ran before every request" without a real RateLimiter's
# 400-call budget or real sleeps getting in the way.
class ThrottleSpy
  attr_reader :calls

  def initialize
    @calls = 0
  end

  def throttle!
    @calls += 1
  end
end

RSpec.describe UmApi::Client do
  around do |example|
    original = %w[UM_API_BASE_URL UM_API_TOKEN_URL UM_API_CLIENT_ID UM_API_CLIENT_SECRET].index_with { |key| ENV[key] }

    ENV["UM_API_BASE_URL"] = UmApiStubs::DEFAULT_BASE_URL
    ENV["UM_API_TOKEN_URL"] = UmApiStubs::DEFAULT_TOKEN_URL
    ENV["UM_API_CLIENT_ID"] = "test-client"
    ENV["UM_API_CLIENT_SECRET"] = "test-secret"

    example.run

    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  describe "constructor defaults" do
    it "constructs a fresh TokenCache and RateLimiter when none are given" do
      client = described_class.new

      expect(client.instance_variable_get(:@token_cache)).to be_a(UmApi::TokenCache)
      expect(client.instance_variable_get(:@rate_limiter)).to be_a(UmApi::RateLimiter)
    end
  end

  describe "#get_json" do
    it "sends the bearer token, client id, and accept headers, and returns the parsed JSON body" do
      stub_um_token(scope: "buildings")
      stub = stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json")
        .with(headers: {
          "Authorization" => "Bearer test-um-api-token-abc123",
          "x-ibm-client-id" => "test-client",
          "Accept" => "application/json"
        })
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      body = client.get_json("/bf/Buildings/v2/Campuses", scope: "buildings")

      expect(body["Campuses"]["Campus"].map { |c| c["CampusCd"] }).to contain_exactly("100", "250")
      expect(stub).to have_been_requested
    end

    # Real param name (sync-fix Task 1): the old `fiscalYear` example pinned
    # a param no phase sends anymore (UmApi.fiscal_year was deleted once
    # Sync::UpdateBuildings stopped using it) — `$start_index` is the real
    # param #fetch_all sends, but #get_json itself is param-name-agnostic,
    # so any real query string proves the same "params flow through" fact.
    it "sends given params as the query string" do
      stub_um_token(scope: "buildings")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json", query: { "$start_index" => "0" })
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      body = client.get_json("/bf/Buildings/v2/Campuses", params: { "$start_index" => "0" }, scope: "buildings")

      expect(body["Campuses"]["Campus"].size).to eq(2)
    end

    it "increments call_count once per HTTP request made" do
      stub_um_token(scope: "buildings")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json")
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      client.get_json("/bf/Buildings/v2/Campuses", scope: "buildings")
      client.get_json("/bf/Buildings/v2/Campuses", scope: "buildings")

      expect(client.call_count).to eq(2)
    end

    it "calls rate_limiter.throttle! once before the request" do
      stub_um_token(scope: "buildings")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json")
      spy = ThrottleSpy.new
      client = described_class.new(rate_limiter: spy)

      client.get_json("/bf/Buildings/v2/Campuses", scope: "buildings")

      expect(spy.calls).to eq(1)
    end

    # Teeth for "before EVERY request": if throttle! ran AFTER the HTTP
    # call (or not at all), a raising rate limiter would still let the
    # request reach WebMock. Only throttle!-before-send means a raise
    # there prevents the request from ever being made.
    it "throttles before sending, so a throttle! failure prevents the HTTP call" do
      stub_um_token(scope: "buildings")
      stub = stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json")
      raising_limiter = Class.new { def throttle! = raise("budget exhausted") }.new
      client = described_class.new(rate_limiter: raising_limiter)

      expect { client.get_json("/bf/Buildings/v2/Campuses", scope: "buildings") }
        .to raise_error("budget exhausted")
      expect(stub).not_to have_been_requested
    end

    describe "status -> error mapping" do
      {
        401 => UmApi::Unauthorized,
        403 => UmApi::Unauthorized,
        404 => UmApi::NotFound,
        429 => UmApi::RateLimited,
        500 => UmApi::ServerError,
        503 => UmApi::ServerError,
        400 => UmApi::ServerError # "other non-2xx" catch-all
      }.each do |status, error_class|
        it "raises #{error_class} for a #{status} response" do
          stub_um_token(scope: "buildings")
          stub_request(:get, "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2/Campuses")
            .to_return(status: status, body: "")
          client = described_class.new(rate_limiter: ThrottleSpy.new)

          expect { client.get_json("/bf/Buildings/v2/Campuses", scope: "buildings") }
            .to raise_error(error_class)
        end
      end
    end
  end

  # #fetch_all is the real-gateway-shaped pagination method (see
  # .superpowers/sdd/sync-fix-plan.md §1): real U-M listing endpoints wrap
  # their array TWO levels deep in the body (e.g. `resp["Campuses"]
  # ["Campus"]`) and paginate via `$start_index`/`$count` query params,
  # stopping when a page comes back shorter than `$count` — there is no
  # `Link: rel="next"` header to follow. The old `#each_page` (a `limit`
  # param + "whichever top-level value is an Array" auto-detection +
  # `Link: rel="next"` header walk) never matched a real response — it was
  # removed in sync-fix Task 5 once every phase migrated to #fetch_all.
  describe "#fetch_all" do
    it "fetches every row of a single-page listing by digging through the two-level array_path" do
      stub_um_token(scope: "buildings")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses.json",
        query: { "$start_index" => "0", "$count" => "1000" })
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      rows = client.fetch_all("/bf/Buildings/v2/Campuses", array_path: %w[Campuses Campus], scope: "buildings")

      expect(rows.map { |row| row["CampusCd"] }).to contain_exactly("100", "250")
      expect(client.call_count).to eq(1)
    end

    it "sends $start_index and $count (not the old limit param) as the query string" do
      stub_um_token(scope: "buildings")
      stub = stub_request(:get, "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2/Campuses")
        .with(query: { "$start_index" => "0", "$count" => "1000" })
        .to_return(status: 200, headers: UmApiStubs::JSON_RESPONSE_HEADERS, body: um_api_fixture("fetch_all_campuses.json"))
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      client.fetch_all("/bf/Buildings/v2/Campuses", array_path: %w[Campuses Campus], scope: "buildings")

      expect(stub).to have_been_requested
    end

    # Teeth: page 1 comes back with exactly PAGE_SIZE (1000) rows, which
    # must force a second request at $start_index=1000 ($count still
    # 1000); page 2 comes back with fewer than PAGE_SIZE rows, which must
    # stop the loop. Getting either half wrong — never requesting page 2,
    # or looping forever after a short page — fails this example. Also
    # proves the two-level array_path dig works against a DIFFERENT key
    # pair (ListOfBldgs/Buildings) than the single-page example above, so
    # array_path isn't accidentally hardcoded to Campuses/Campus.
    it "requests a second page when the first is exactly PAGE_SIZE, and stops once a page is short" do
      stub_um_token(scope: "buildings")
      page1_rows = Array.new(UmApi::Client::PAGE_SIZE) { |i| { "BuildingRecordNumber" => "page1-#{i}" } }
      page2_rows = [
        { "BuildingRecordNumber" => "9001" },
        { "BuildingRecordNumber" => "9002" }
      ]
      page1_stub = stub_request(:get, "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2/BuildingInfo")
        .with(query: { "$start_index" => "0", "$count" => "1000" })
        .to_return(status: 200, headers: UmApiStubs::JSON_RESPONSE_HEADERS,
          body: { "ListOfBldgs" => { "Buildings" => page1_rows } }.to_json)
      page2_stub = stub_request(:get, "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2/BuildingInfo")
        .with(query: { "$start_index" => "1000", "$count" => "1000" })
        .to_return(status: 200, headers: UmApiStubs::JSON_RESPONSE_HEADERS,
          body: { "ListOfBldgs" => { "Buildings" => page2_rows } }.to_json)
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      rows = client.fetch_all("/bf/Buildings/v2/BuildingInfo", array_path: %w[ListOfBldgs Buildings], scope: "buildings")

      expect(rows.size).to eq(UmApi::Client::PAGE_SIZE + 2)
      expect(rows.last(2).map { |row| row["BuildingRecordNumber"] }).to eq(%w[9001 9002])
      expect(page1_stub).to have_been_requested.once
      expect(page2_stub).to have_been_requested.once
      expect(client.call_count).to eq(2)
    end

    it "returns an empty array, in a single request, when array_path digs to an empty listing" do
      stub_um_token(scope: "buildings")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "fetch_all_campuses_empty.json",
        query: { "$start_index" => "0", "$count" => "1000" })
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      rows = client.fetch_all("/bf/Buildings/v2/Campuses", array_path: %w[Campuses Campus], scope: "buildings")

      expect(rows).to eq([])
      expect(client.call_count).to eq(1)
    end

    it "returns an empty array without raising when array_path digs into a key the response doesn't have" do
      stub_um_token(scope: "buildings")
      stub_request(:get, "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2/Campuses")
        .with(query: { "$start_index" => "0", "$count" => "1000" })
        .to_return(status: 200, headers: UmApiStubs::JSON_RESPONSE_HEADERS, body: { "SomethingElse" => {} }.to_json)
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      rows = client.fetch_all("/bf/Buildings/v2/Campuses", array_path: %w[Campuses Campus], scope: "buildings")

      expect(rows).to eq([])
    end
  end
end
