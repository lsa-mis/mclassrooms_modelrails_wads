# frozen_string_literal: true

# Fake U-M gateway for the phase 2 ingestion specs (Task 2 of
# planning/plans/phase-2-ingestion.md). Every sync-phase spec (Tasks 3-13)
# stubs the U-M Facilities API through these two helpers instead of hitting
# the network — WebMock is globally locked down in spec/rails_helper.rb
# (`WebMock.disable_net_connect!(allow_localhost: true)`), so any HTTP call
# that isn't stubbed here (or via Localhost, for Capybara/Playwright) raises.
#
# IMPORTANT — fixture-shape disclaimer: the JSON under spec/fixtures/um_api/
# (envelope shape, field names like `CampusCd`/`BldRecNbr`/`RmRecNbr`, the
# `Link: rel="next"` pagination convention) is a BEST-EFFORT RECONSTRUCTION
# of the real U-M gateway, written before any credentialed access to it. It
# is NOT verified against the live API. Phase 8's cutover task is where that
# gets confirmed — if the real shape differs, only two kinds of files need
# to change: these fixtures, and each phase service's `parse_*` methods
# (Sync::UpdateCampuses#parse_campus and friends). No other code should ever
# reach into a raw API response hash directly; that isolation is the entire
# point of funneling every field access through a named `parse_*` method.
module UmApiStubs
  JSON_RESPONSE_HEADERS = { "Content-Type" => "application/json" }.freeze

  # Placeholder gateway hosts. Task 3 (UmApi::TokenCache) and Task 5
  # (UmApi::Client) read UM_API_TOKEN_URL / UM_API_BASE_URL from ENV with no
  # default (`ENV.fetch`), so once those are wired into .env.example the env
  # var wins here too — these constants only matter until then, and as the
  # fallback in environments (e.g. this checkout, today) where the vars
  # aren't set yet.
  DEFAULT_TOKEN_URL = "https://gw.api.it.umich.edu/um/oauth2/token"
  DEFAULT_BASE_URL = "https://gw.api.it.umich.edu/um"

  # Stubs the OAuth2 client-credentials token endpoint (UmApi::TokenCache#fetch)
  # for one `scope` ("buildings" | "classrooms" | "department"). Always
  # returns fixtures/um_api/token.json — every scope gets the same fake
  # bearer token, since the fixture only needs to prove the plumbing works,
  # not model per-scope token differences.
  def stub_um_token(scope:)
    stub_request(:post, um_api_token_url)
      .with(body: hash_including(grant_type: "client_credentials", scope: scope))
      .to_return(status: 200, headers: JSON_RESPONSE_HEADERS, body: um_api_fixture("token.json"))
  end

  # Stubs a single GET against the U-M gateway, returning the named fixture
  # file's raw JSON. `path` is the endpoint path (e.g.
  # "/bf/Buildings/v2/Campuses"); `query` narrows the stub to a specific
  # query-string (default `{}` matches a request with no query params at
  # all — pass the real params when the code under test sends any).
  # `next_link:` (a full URL string) attaches a `Link: <url>; rel="next"`
  # response header so UmApi::Client#each_page has something to follow;
  # omit it (the default) to represent the last page.
  def stub_um_get(path, fixture:, query: {}, next_link: nil)
    headers = JSON_RESPONSE_HEADERS
    headers = headers.merge("Link" => %(<#{next_link}>; rel="next")) if next_link

    stub_request(:get, "#{um_api_base_url}#{path}")
      .with(query: query)
      .to_return(status: 200, headers: headers, body: um_api_fixture(fixture))
  end

  private

  def um_api_token_url
    ENV.fetch("UM_API_TOKEN_URL", DEFAULT_TOKEN_URL)
  end

  def um_api_base_url
    ENV.fetch("UM_API_BASE_URL", DEFAULT_BASE_URL)
  end

  def um_api_fixture(name)
    Rails.root.join("spec/fixtures/um_api", name).read
  end
end

RSpec.configure do |config|
  config.include UmApiStubs
end
