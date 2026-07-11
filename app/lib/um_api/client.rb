# frozen_string_literal: true

# U-M Facilities gateway HTTP client (Task 5 of
# planning/plans/phase-2-ingestion.md; roadmap Lib section). Every sync
# service (Tasks 6+) goes through this one class instead of touching
# Net::HTTP directly, so pagination, auth headers, and status->error
# mapping all live in exactly one place. Per the brief, a single
# persistent-connection helper is unnecessary at this volume — plain
# per-request Net::HTTP is fine and simpler.
#
# #get_json fetches one URL and parses its JSON body. #each_page walks a
# paginated listing endpoint: it requests PAGE_SIZE items per page and
# yields every item from every page's array, following the response's
# `Link: <url>; rel="next"` header until a page omits it.
#
# PAGE_SIZE_PARAM disclaimer: like spec/support/um_api_stubs.rb's fixture
# shapes, the real U-M gateway's page-size query parameter name has not
# been confirmed against credentialed access (see that file's header
# comment). "limit" is this client's best-effort guess. If phase 8's
# cutover finds the real gateway uses a different name, only this one
# constant needs to change — every sync service calls #each_page with its
# own `params` and never touches pagination directly.
#
# Auth/headers: every request carries `Authorization: Bearer <token>`
# (from `token_cache.token_for(scope)`), `x-ibm-client-id` (the IBM API
# Connect gateway convention U-M's Facilities API sits behind), and
# `Accept: application/json`.
#
# Rate limiting: every single HTTP request — each #get_json call, and
# each page fetched inside #each_page — runs `rate_limiter.throttle!`
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
    PAGE_SIZE_PARAM = "limit"

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
    # Returns the full concatenated Array of rows (unlike #each_page, which
    # yields one item at a time) — callers that want to iterate can just
    # call `.each` on the result.
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

    # Walks a paginated listing endpoint, yielding every item from every
    # page to the block. Requests PAGE_SIZE items on the first page and
    # follows the `Link: <url>; rel="next"` response header — which is
    # expected to be a complete, ready-to-fetch URL — until a page omits
    # it.
    #
    # DEPRECATED (kept temporarily so every phase's existing spec stays
    # green — see `.superpowers/sdd/sync-fix-plan.md` Task 1/5): the real
    # gateway does not send a usable `Link: rel="next"` header and expects
    # `$start_index`/`$count`, not `limit` — #each_page's pagination never
    # advances against a real response. Use #fetch_all instead; every
    # phase will be migrated off #each_page and this method removed.
    def each_page(path, params: {}, scope:)
      uri = build_uri(path, params.merge(PAGE_SIZE_PARAM => PAGE_SIZE))

      loop do
        response = request(uri, scope: scope)
        page_items(JSON.parse(response.body)).each { |item| yield item }

        next_url = next_link(response["Link"])
        break unless next_url

        uri = URI(next_url)
      end
    end

    private

    def build_uri(path, params)
      uri = URI("#{ENV.fetch("UM_API_BASE_URL")}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?
      uri
    end

    # Every fixture (and, per the roadmap, every real listing endpoint)
    # wraps its items in a single top-level key ("Buildings", "Rooms",
    # "Classrooms", ...) whose value is the array of items. The key name
    # varies per endpoint, so rather than hardcode one, this grabs
    # whichever top-level value is an Array.
    def page_items(body)
      body.values.find { |value| value.is_a?(Array) } || []
    end

    # Parses a `Link` header shaped like `<url>; rel="next"`, possibly
    # with other comma-separated rel values (e.g. `<url1>; rel="first",
    # <url2>; rel="next"`), and returns the rel="next" URL — or nil if
    # there isn't one (last page) or the header is absent entirely.
    #
    # Scans for every `<url>; rel="x"` pair instead of splitting the header
    # on a bare "," first: a naive split breaks as soon as any URL in the
    # header (rel="next" or otherwise) contains a literal comma — e.g. a
    # query string like `?ids=1,2,3` — silently truncating pagination
    # (returns nil, loop stops early, no error) instead of raising.
    def next_link(header)
      return nil unless header

      header.to_s.scan(/<([^>]+)>\s*;\s*rel="?([^",;]+)"?/).find { |_url, rel| rel == "next" }&.first
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
