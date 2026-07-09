require "rails_helper"

# Self-test for the phase 2 WebMock harness (spec/support/um_api_stubs.rb).
# Nothing in app/ consumes these helpers yet — Task 3+ of
# planning/plans/phase-2-ingestion.md builds UmApi::TokenCache/Client against
# them — so this spec proves the plumbing itself: a raw Net::HTTP request
# (standing in for the future gateway client) hits WebMock and gets back the
# named fixture file's exact JSON, before any real production code depends
# on it.
RSpec.describe UmApiStubs do
  describe "#stub_um_token" do
    it "stubs the token endpoint for the given scope with the token fixture" do
      stub_um_token(scope: "buildings")

      response = Net::HTTP.post_form(
        URI(UmApiStubs::DEFAULT_TOKEN_URL),
        grant_type: "client_credentials", scope: "buildings",
        client_id: "test-client", client_secret: "test-secret"
      )
      body = JSON.parse(response.body)

      expect(response).to be_a(Net::HTTPSuccess)
      expect(body["access_token"]).to eq("test-um-api-token-abc123")
      expect(body["expires_in"]).to eq(3600)
    end

    it "only stubs the scope it was told about" do
      stub_um_token(scope: "buildings")

      expect do
        Net::HTTP.post_form(
          URI(UmApiStubs::DEFAULT_TOKEN_URL),
          grant_type: "client_credentials", scope: "classrooms",
          client_id: "test-client", client_secret: "test-secret"
        )
      end.to raise_error(WebMock::NetConnectNotAllowedError)
    end
  end

  describe "#stub_um_get" do
    it "returns the named fixture's raw JSON for a matching GET" do
      stub_um_get("/bf/Buildings/v2/Campuses", fixture: "campuses.json")

      response = Net::HTTP.get_response(URI("#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2/Campuses"))
      body = JSON.parse(response.body)

      expect(response).to be_a(Net::HTTPSuccess)
      expect(body["Campuses"].map { |c| c["CampusCd"] }).to contain_exactly("100", "250")
    end

    it "matches only the given query params, not an unqualified request" do
      stub_um_get("/bf/Buildings/v2", fixture: "buildings_page1.json", query: { fiscalYear: "2027" })

      response = Net::HTTP.get_response(URI("#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2?fiscalYear=2027"))
      expect(JSON.parse(response.body)["Buildings"].size).to eq(2)

      expect do
        Net::HTTP.get_response(URI("#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2"))
      end.to raise_error(WebMock::NetConnectNotAllowedError)
    end

    it "attaches a Link: rel=\"next\" header when next_link is given" do
      next_page_url = "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2?page=2"
      stub_um_get("/bf/Buildings/v2", fixture: "buildings_page1.json", next_link: next_page_url)

      response = Net::HTTP.get_response(URI("#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2"))

      expect(response["Link"]).to eq(%(<#{next_page_url}>; rel="next"))
    end

    it "omits the Link header when next_link is not given (last page)" do
      stub_um_get("/bf/Buildings/v2", fixture: "buildings_page2.json")

      response = Net::HTTP.get_response(URI("#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2"))

      expect(response["Link"]).to be_nil
    end
  end

  describe "fixture inventory" do
    it "ships every fixture file the roadmap's Test fixtures section names" do
      %w[
        token.json campuses.json buildings_page1.json buildings_page2.json
        rooms_1005046.json rooms_1005090.json classroom_list.json
        characteristics_MLB1200.json contacts_MLB1200.json
      ].each do |name|
        expect(Rails.root.join("spec/fixtures/um_api", name)).to exist
      end
    end

    it "produces valid JSON for every fixture file" do
      Dir[Rails.root.join("spec/fixtures/um_api/*.json")].each do |path|
        expect { JSON.parse(File.read(path)) }.not_to raise_error, "invalid JSON in #{path}"
      end
    end
  end
end
