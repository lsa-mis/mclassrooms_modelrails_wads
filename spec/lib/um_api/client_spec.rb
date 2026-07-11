require "rails_helper"

# Task 5 of planning/plans/phase-2-ingestion.md: UmApi::Client is the single
# HTTP entry point every sync service (Tasks 6+) uses to talk to the U-M
# Facilities gateway (roadmap Lib section). #get_json fetches one URL;
# #each_page walks a paginated listing endpoint, following `Link: <url>;
# rel="next"` headers until a page omits one. Every request — each
# #get_json call, and each page inside #each_page — runs
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
      stub = stub_um_get("/bf/Buildings/v2/Campuses", fixture: "campuses.json")
        .with(headers: {
          "Authorization" => "Bearer test-um-api-token-abc123",
          "x-ibm-client-id" => "test-client",
          "Accept" => "application/json"
        })
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      body = client.get_json("/bf/Buildings/v2/Campuses", scope: "buildings")

      expect(body["Campuses"].map { |c| c["CampusCd"] }).to contain_exactly("100", "250")
      expect(stub).to have_been_requested
    end

    it "sends given params as the query string" do
      stub_um_token(scope: "buildings")
      stub_um_get("/bf/Buildings/v2", fixture: "buildings_page1.json", query: { "fiscalYear" => "2027" })
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      body = client.get_json("/bf/Buildings/v2", params: { fiscalYear: "2027" }, scope: "buildings")

      expect(body["Buildings"].size).to eq(2)
    end

    it "increments call_count once per HTTP request made" do
      stub_um_token(scope: "buildings")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "campuses.json")
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      client.get_json("/bf/Buildings/v2/Campuses", scope: "buildings")
      client.get_json("/bf/Buildings/v2/Campuses", scope: "buildings")

      expect(client.call_count).to eq(2)
    end

    it "calls rate_limiter.throttle! once before the request" do
      stub_um_token(scope: "buildings")
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "campuses.json")
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
      stub = stub_um_get("/bf/Buildings/v2/Campuses", fixture: "campuses.json")
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

  describe "#each_page" do
    it "requests PAGE_SIZE (1000) items per page via the limit param" do
      stub_um_token(scope: "buildings")
      stub = stub_um_get("/bf/Buildings/v2", fixture: "buildings_page2.json", query: { "limit" => "1000" })
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      client.each_page("/bf/Buildings/v2", scope: "buildings") { |_item| }

      expect(stub).to have_been_requested
    end

    # Teeth: buildings_page1 has 2 items ("Modern Languages Building",
    # "Angell Hall") and next_link points at page 2, whose fixture has one
    # DISTINCT item ("Danto Engineering Development Center") not present
    # on page 1. All three items must be yielded — page 1's alone, or
    # page 2 fetched but not yielded, would both fail this — and the loop
    # must stop after page 2, which is stubbed with no next_link (no Link
    # header at all).
    it "yields items across both pages and stops when there is no next link" do
      stub_um_token(scope: "buildings")
      next_page_url = "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2?page=2"
      stub_um_get("/bf/Buildings/v2", fixture: "buildings_page1.json", query: { "limit" => "1000" },
        next_link: next_page_url)
      last_page_stub = stub_um_get("/bf/Buildings/v2", fixture: "buildings_page2.json", query: { "page" => "2" })
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      names = []
      client.each_page("/bf/Buildings/v2", scope: "buildings") { |item| names << item["BldName"] }

      expect(names).to contain_exactly(
        "Modern Languages Building", "Angell Hall", "Danto Engineering Development Center"
      )
      expect(last_page_stub).to have_been_requested.once
      expect(client.call_count).to eq(2)
    end

    # Teeth for next_link's Link-header parsing: the header carries BOTH a
    # rel="prev" and a rel="next" entry in one comma-separated value, and
    # BOTH urls contain a literal comma in their own query string (e.g.
    # `?ids=1,2,3`). The old implementation split the whole header on a
    # bare "," before regex-matching each fragment, so a comma inside the
    # rel="next" URL split that URL's `<...>` across two fragments and
    # next_link returned nil — each_page would silently stop after page 1
    # with no error. Scanning for every `<url>; rel="x"` pair instead of
    # splitting first fixes that: this must yield page 2's item too.
    it "follows only the rel=\"next\" link when the header also carries a rel=\"prev\" link, even when both URLs contain commas" do
      stub_um_token(scope: "buildings")
      prev_url = "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2?ids=9,8,7"
      next_url = "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2?page=2&ids=1,2,3"
      multi_rel_link_header = %(<#{prev_url}>; rel="prev", <#{next_url}>; rel="next")

      stub_request(:get, "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2")
        .with(query: { "limit" => "1000" })
        .to_return(
          status: 200,
          headers: UmApiStubs::JSON_RESPONSE_HEADERS.merge("Link" => multi_rel_link_header),
          body: um_api_fixture("buildings_page1.json")
        )
      next_page_stub = stub_request(:get, next_url)
        .to_return(status: 200, headers: UmApiStubs::JSON_RESPONSE_HEADERS, body: um_api_fixture("buildings_page2.json"))
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      names = []
      client.each_page("/bf/Buildings/v2", scope: "buildings") { |item| names << item["BldName"] }

      expect(names).to contain_exactly(
        "Modern Languages Building", "Angell Hall", "Danto Engineering Development Center"
      )
      expect(next_page_stub).to have_been_requested.once
    end

    it "runs rate_limiter.throttle! once per page fetched" do
      stub_um_token(scope: "buildings")
      next_page_url = "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2?page=2"
      stub_um_get("/bf/Buildings/v2", fixture: "buildings_page1.json", query: { "limit" => "1000" },
        next_link: next_page_url)
      stub_um_get("/bf/Buildings/v2", fixture: "buildings_page2.json", query: { "page" => "2" })
      spy = ThrottleSpy.new
      client = described_class.new(rate_limiter: spy)

      client.each_page("/bf/Buildings/v2", scope: "buildings") { |_item| }

      expect(spy.calls).to eq(2)
    end

    it "increments call_count once per page fetched" do
      stub_um_token(scope: "buildings")
      stub_um_get("/bf/Buildings/v2", fixture: "buildings_page2.json", query: { "limit" => "1000" })
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      client.each_page("/bf/Buildings/v2", scope: "buildings") { |_item| }

      expect(client.call_count).to eq(1)
    end

    it "raises UmApi::RateLimited from within each_page on a 429, without swallowing it" do
      stub_um_token(scope: "buildings")
      stub_request(:get, "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2")
        .with(query: { "limit" => "1000" })
        .to_return(status: 429, body: "")
      client = described_class.new(rate_limiter: ThrottleSpy.new)

      expect { client.each_page("/bf/Buildings/v2", scope: "buildings") { |_item| } }
        .to raise_error(UmApi::RateLimited)
    end
  end

  # #fetch_all is the real-gateway-shaped replacement for #each_page (see
  # .superpowers/sdd/sync-fix-plan.md §1): real U-M listing endpoints wrap
  # their array TWO levels deep in the body (e.g. `resp["Campuses"]
  # ["Campus"]`) and paginate via `$start_index`/`$count` query params,
  # stopping when a page comes back shorter than `$count` — there is no
  # `Link: rel="next"` header to follow. #each_page's `limit` param and
  # "whichever top-level value is an Array" auto-detection never match a
  # real response, so it silently yields zero rows; #fetch_all fixes both
  # defects side by side with #each_page, which stays untouched (and green)
  # until every phase is migrated off it.
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
