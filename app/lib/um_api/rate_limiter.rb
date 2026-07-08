# Self-imposed client-side rate limiting for the U-M Facilities gateway
# (roadmap Lib section §6.1; planning/plans/phase-2-ingestion.md Task 4).
# Every sync service (Tasks 6+) calls #throttle! before each request to stay
# under a budget well inside whatever the real gateway limit is, and wraps
# each request in #backoff_429 so a transient HTTP 429 (UmApi::RateLimited,
# raised by UmApi::Client, Task 5) sleeps-and-retries instead of aborting
# the whole sync run.
#
# #throttle!: tracks call timestamps in a rolling 60s window (a plain Array
# is fine at 400 calls/min — see brief). On the 401st call landing inside
# the window, sleeps BACKOFF_SLEEP_SECONDS (61s) via the injected `sleeper`
# and resets the window, so a fresh budget starts clean rather than
# immediately re-tripping on stale timestamps the next call.
#
# #backoff_429: yields the block; on UmApi::RateLimited it sleeps
# BACKOFF_SLEEP_SECONDS and retries, up to MAX_BACKOFF_ATTEMPTS (10) retries
# total, then re-raises so the caller's Result.failure mapping (Tasks 6+)
# still fires for a gateway that's genuinely down.
#
# #sleep_count: total sleeps performed by either method — feeds each sync
# phase's `rate_limit_sleeps` counter (roadmap).
#
# `sleeper:` / `clock:` are injectable exactly like UmApi::TokenCache's
# `clock:` — specs inject a fake sleeper (records calls, returns
# immediately) and a fake clock (advanced manually), so no spec here ever
# really sleeps or waits.
#
# Thread-safety: a Mutex guards the shared @timestamps array and the sleep
# counter, matching TokenCache's posture, since #throttle! mutates shared
# state on every call and concurrent sync services could otherwise race.
# The Mutex only wraps the quick bookkeeping (evict/record/check-and-reset),
# never the sleep itself, so one caller's real 61s sleep doesn't block every
# other caller's throttle! check for the duration.
module UmApi
  class RateLimiter
    CALLS_PER_MINUTE = 400
    WINDOW_SECONDS = 60
    BACKOFF_SLEEP_SECONDS = 61
    MAX_BACKOFF_ATTEMPTS = 10

    def initialize(sleeper: Kernel.method(:sleep), clock: Time)
      @sleeper = sleeper
      @clock = clock
      @timestamps = []
      @sleep_count = 0
      @mutex = Mutex.new
    end

    # Call before every request against the gateway. Evicts timestamps
    # older than the rolling window, records this call, and — if that's
    # the 401st timestamp still inside the window — sleeps 61s and resets
    # the window so the next call starts a fresh budget.
    def throttle!
      tripped = @mutex.synchronize do
        now = @clock.now
        @timestamps.reject! { |timestamp| now - timestamp >= WINDOW_SECONDS }
        @timestamps << now

        next false unless @timestamps.size > CALLS_PER_MINUTE

        @timestamps = []
        true
      end

      return unless tripped

      @sleeper.call(BACKOFF_SLEEP_SECONDS)
      @mutex.synchronize { @sleep_count += 1 }
    end

    # Yields the block. On UmApi::RateLimited (HTTP 429) sleeps 61s and
    # retries, up to MAX_BACKOFF_ATTEMPTS times, then re-raises.
    def backoff_429
      attempts = 0

      begin
        yield
      rescue UmApi::RateLimited
        attempts += 1
        raise if attempts > MAX_BACKOFF_ATTEMPTS

        @sleeper.call(BACKOFF_SLEEP_SECONDS)
        @mutex.synchronize { @sleep_count += 1 }
        retry
      end
    end

    def sleep_count
      @mutex.synchronize { @sleep_count }
    end
  end
end
