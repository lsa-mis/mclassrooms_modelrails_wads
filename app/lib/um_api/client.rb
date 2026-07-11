# frozen_string_literal: true

# U-M Facilities gateway HTTP client (Task 5 of
# planning/plans/phase-2-ingestion.md; roadmap Lib section). Every sync
# service (Tasks 6+) goes through this one class instead of touching
# Net::HTTP directly, so pagination, auth headers, and status->error
# mapping all live in exactly one place. Per the brief, a single
# persistent-connection helper is unnecessary at this volume — plain
# per-request Net::HTTP is fine and simpler.
#
# #get_json fetches one URL and parses its JSON body. #fetch_all walks a
# paginated listing endpoint: it requests PAGE_SIZE items per page (real
# `$start_index`/`$count` query params, confirmed live — sync-fix Task 1)
# and returns every row from every page, stopping once a page comes back
# shorter than PAGE_SIZE.
#
# Auth/headers: every request carries `Authorization: Bearer <token>`
# (from `token_cache.token_for(scope)`), `x-ibm-client-id` (the IBM API
# Connect gateway convention U-M's Facilities API sits behind), and
# `Accept: application/json`.
#
# Rate limiting: every single HTTP request — each #get_json call, and
# each page fetched inside #fetch_all — runs `rate_limiter.throttle!`
# first (before the request is sent), so the self-imposed budget
# (UmApi::RateLimiter) sees every call the gateway actually receives, not
# just the "logical" request the caller made.
#
# Errors: a non-2xx response raises a UmApi::Error subclass (see
# app/lib/um_api.rb) instead of returning silently. A 429 is surfaced as
# UmApi::RateLimited to the caller rather than retried here —
# RateLimiter#backoff_429 is the caller's tool for that (roadmap:
# "callers decide whether to backoff_429"), so this class stays a dumb,
# predictable HTTP layer.
#
# #call_count is a running total of HTTP requests actually sent (feeds
# each sync phase's `api_calls` counter, roadmap).
#
# #rate_limiter is exposed (Task 6) so Sync::BasePhase can read
# `rate_limiter.sleep_count` before/after a phase runs and diff the two —
# the same before/after pattern #call_count itself supports — without this
# class needing to know anything about phases or counters itself.
module UmApi
  class Client
    PAGE_SIZE = 1000

    attr_reader :call_count, :rate_limiter

    def initialize(token_cache: TokenCache.new, rate_limiter: RateLimiter.new)
      @token_cache = token_cache
      @rate_limiter = rate_limiter
      @call_count = 0
    end

    # Fetches `path` (+ `params` as a query string) and returns the parsed
    # JSON body as a Hash. Raises a UmApi::Error subclass on any non-2xx
    # response.
    def get_json(path, params: {}, scope:)
      response = request(build_uri(path, params), scope: scope)
      JSON.parse(response.body)
    end

    # Fetches every row of a paginated U-M listing endpoint, the way the
    # real gateway actually paginates (verified live — see
    # `lib/tasks/um_import.rake`'s `paged_fetch`, the proven reference this
    # mirrors): request params are `$start_index` (0-based offset) and
    # `$count` (page size, `PAGE_SIZE`), and a page shorter than `$count`
    # means it was the last page — there is no reliable `Link: rel="next"`
    # header to follow on real responses.
    #
    # Every real listing endpoint wraps its array TWO levels deep in the
    # JSON body (e.g. `{"Campuses" => {"Campus" => [...]}}`), not in a
    # single top-level key — `array_path` is the list of keys to dig
    # through to reach that array (e.g. `%w[Campuses Campus]`). A missing
    # or non-Hash step in the dig (including an altogether-empty listing)
    # yields an empty page rather than raising.
    #
    # Returns the full concatenated Array of rows — callers that want to
    # iterate can just call `.each` on the result.
    def fetch_all(path, array_path:, scope:, params: {})
      rows = []
      start_index = 0

      loop do
        body = get_json(path, params: params.merge("$start_index" => start_index, "$count" => PAGE_SIZE), scope: scope)
        page = Array(array_path.reduce(body) { |acc, key| acc.is_a?(Hash) ? acc[key] : nil })
        rows.concat(page)
        break if page.size < PAGE_SIZE

        start_index += PAGE_SIZE
      end

      rows
    end

    private

    def build_uri(path, params)
      uri = URI("#{ENV.fetch("UM_API_BASE_URL")}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?
      uri
    end

    def request(uri, scope:)
      @rate_limiter.throttle!

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      get = Net::HTTP::Get.new(uri)
      get["Authorization"] = "Bearer #{@token_cache.token_for(scope)}"
      get["x-ibm-client-id"] = ENV["UM_API_CLIENT_ID"]
      get["Accept"] = "application/json"

      response = http.request(get)
      @call_count += 1

      raise_for_status(response, uri: uri)
      response
    end

    def raise_for_status(response, uri:)
      code = response.code.to_i
      return if (200..299).cover?(code)

      message = "U-M gateway returned #{code} for #{uri}"

      case code
      when 401, 403
        raise UmApi::Unauthorized, message
      when 404
        raise UmApi::NotFound, message
      when 429
        raise UmApi::RateLimited, message
      else
        raise UmApi::ServerError, message
      end
    end
  end
end
