# Per-scope OAuth2 client-credentials token cache for the U-M Facilities
# gateway (roadmap Lib section; planning/plans/phase-2-ingestion.md Task 3).
# Every sync service (Tasks 6+) needs a bearer token for one of three scopes
# ("buildings" | "classrooms" | "department") before calling UmApi::Client;
# fetching a fresh token per request would hammer the token endpoint, so this
# caches the token per scope until shortly before it actually expires.
#
# Early-expiry buffer: a cached token is treated as expired 60 seconds before
# its real `expires_in` deadline (EARLY_EXPIRY), so an in-flight request never
# starts with a token that goes stale mid-call.
#
# `clock:` defaults to `Time` but accepts any object responding to `.now` —
# specs inject a fake clock and advance it to exercise expiry/refetch without
# a real sleep.
#
# Thread-safety: a single Mutex guards both the cache read and the (rare)
# fetch-and-write, so concurrent callers for the same scope never trigger
# two outstanding token requests, and callers for different scopes never
# corrupt each other's cache entry.
module UmApi
  class TokenCache
    EARLY_EXPIRY = 60

    def initialize(clock: Time)
      @clock = clock
      @tokens = {}
      @mutex = Mutex.new
    end

    # Returns the cached bearer token for `scope`, fetching (and caching) a
    # fresh one if there's no entry yet or the cached entry has passed its
    # early-expiry deadline. Raises UmApi::Unauthorized if the token endpoint
    # responds 401/403.
    def token_for(scope)
      @mutex.synchronize do
        entry = @tokens[scope]
        next entry[:token] if entry && entry[:expires_at] > @clock.now

        @tokens[scope] = fetch(scope)
        @tokens[scope][:token]
      end
    end

    private

    def fetch(scope)
      response = Net::HTTP.post_form(
        URI(ENV.fetch("UM_API_TOKEN_URL")),
        grant_type: "client_credentials",
        scope: scope,
        client_id: ENV.fetch("UM_API_CLIENT_ID"),
        client_secret: ENV.fetch("UM_API_CLIENT_SECRET")
      )

      unless response.is_a?(Net::HTTPSuccess)
        raise UmApi::Unauthorized, "token endpoint returned #{response.code} for scope #{scope}"
      end

      body = JSON.parse(response.body)
      { token: body.fetch("access_token"), expires_at: @clock.now + body.fetch("expires_in").to_i - EARLY_EXPIRY }
    end
  end
end
