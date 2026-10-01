# frozen_string_literal: true

# Minimal stand-ins for the U-M gateway's collaborators, defined once (#1273): no example
# that uses them touches the network or waits on real time.

# The `clock:` argument of UmApi::TokenCache and UmApi::RateLimiter; advance it by assigning #now.
class FakeClock
  attr_accessor :now

  def initialize(now) = @now = now
end

# Records the seconds UmApi::RateLimiter asked to sleep and returns at once.
class FakeSleeper
  attr_reader :calls

  def initialize
    @calls = []
  end

  def call(seconds)
    @calls << seconds
  end
end

# Stands in for UmApi::Client's `rate_limiter:`, counting #throttle! calls instead of throttling.
class ThrottleSpy
  attr_reader :calls

  def initialize
    @calls = 0
  end

  def throttle!
    @calls += 1
  end
end

# Sync::BasePhase records per-phase deltas, so both counts are seedable: a limiter or client
# carried across phases starts each new phase above zero.
class FakeRateLimiter
  attr_accessor :sleep_count

  def initialize(sleep_count: 0)
    @sleep_count = sleep_count
  end
end

class FakeClient
  attr_reader :call_count, :rate_limiter

  def initialize(call_count: 0, rate_limiter: FakeRateLimiter.new)
    @call_count = call_count
    @rate_limiter = rate_limiter
  end

  # Simulates `n` sent requests, as UmApi::Client#call_count counts them.
  def simulate_calls(n)
    @call_count += n
  end
end
