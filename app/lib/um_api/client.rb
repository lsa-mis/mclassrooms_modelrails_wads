# frozen_string_literal: true

module UmApi
  class Client
    PAGE_SIZE = 1000

    attr_reader :call_count, :rate_limiter

    def initialize(token_cache: TokenCache.new, rate_limiter: RateLimiter.new)
      @token_cache = token_cache
      @rate_limiter = rate_limiter
      @call_count = 0
    end

    def get_json(path, params: {}, scope:, remember: false)
      uri = build_uri(path, params)
      body = remember ? (remembered[uri.to_s] ||= request(uri, scope:).body) : request(uri, scope:).body
      JSON.parse(body)
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

      get = Net::HTTP::Get.new(uri)
      get["Authorization"] = "Bearer #{@token_cache.token_for(scope)}"
      get["x-ibm-client-id"] = ENV["UM_API_CLIENT_ID"]
      get["Accept"] = "application/json"

      response = connection(uri).request(get)
      @call_count += 1

      raise_for_status(response, uri: uri)
      response
    end

    def connection(uri)
      @connection = nil unless @connection&.started? && @connection.address == uri.host && @connection.port == uri.port
      @connection ||= Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https")
    end

    def remembered = @remembered ||= {}

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
