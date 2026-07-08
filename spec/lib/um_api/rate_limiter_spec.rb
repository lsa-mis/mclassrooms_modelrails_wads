require "rails_helper"

# Task 4 of planning/plans/phase-2-ingestion.md: UmApi::RateLimiter enforces
# a self-imposed 400-calls/minute budget (#throttle!, roadmap Lib section
# §6.1) and sleep-and-retry backoff on HTTP 429s (#backoff_429), so every
# sync service (Tasks 6+) can call the U-M gateway without worrying about
# tripping the real rate limit or aborting a whole sync run on a transient
# 429. #sleep_count feeds each sync phase's `rate_limit_sleeps` counter.
#
# `sleeper:` (a callable) and `clock:` (anything responding to `.now`) are
# both injected exactly like UmApi::TokenCache's `clock:` — FakeSleeper
# below just records the seconds it was asked to sleep and returns
# immediately, and FakeClock is the same minimal fake used in
# token_cache_spec.rb (reopened here; identical definition, no conflict).
# No example in this file ever sleeps or waits on real time.
class FakeClock
  attr_accessor :now

  def initialize(now) = @now = now
end

class FakeSleeper
  attr_reader :calls

  def initialize
    @calls = []
  end

  def call(seconds)
    @calls << seconds
  end
end

RSpec.describe UmApi::RateLimiter do
  describe "#throttle!" do
    it "does not sleep for the first 400 calls within a minute" do
      sleeper = FakeSleeper.new
      limiter = described_class.new(sleeper: sleeper, clock: FakeClock.new(Time.utc(2026, 1, 1)))

      400.times { limiter.throttle! }

      expect(sleeper.calls).to eq([])
      expect(limiter.sleep_count).to eq(0)
    end

    it "sleeps exactly once, for 61 seconds, when the 401st call arrives within the window" do
      sleeper = FakeSleeper.new
      limiter = described_class.new(sleeper: sleeper, clock: FakeClock.new(Time.utc(2026, 1, 1)))

      401.times { limiter.throttle! }

      expect(sleeper.calls).to eq([ 61 ])
      expect(limiter.sleep_count).to eq(1)
    end

    it "resets the window after sleeping so the next batch of calls doesn't immediately re-sleep" do
      sleeper = FakeSleeper.new
      limiter = described_class.new(sleeper: sleeper, clock: FakeClock.new(Time.utc(2026, 1, 1)))

      401.times { limiter.throttle! } # trips the one sleep and resets the window
      400.times { limiter.throttle! } # a fresh window's worth of calls — must NOT sleep again

      expect(sleeper.calls).to eq([ 61 ])
      expect(limiter.sleep_count).to eq(1)
    end

    # Teeth: if eviction were broken (reject! a no-op, or missing entirely),
    # the second batch of 400 calls would land on top of the first 400
    # still sitting in the array, tripping a sleep on the very first call
    # of the second batch (401st call overall) even though 61s have
    # passed. Only correct eviction of the now-stale first batch keeps the
    # second batch under budget with zero sleeps.
    it "evicts calls older than the 60s window so they don't count toward the budget" do
      clock = FakeClock.new(Time.utc(2026, 1, 1))
      sleeper = FakeSleeper.new
      limiter = described_class.new(sleeper: sleeper, clock: clock)

      400.times { limiter.throttle! } # fills the window exactly to capacity
      clock.now += 61 # advance past the 60s window
      400.times { limiter.throttle! } # a fresh 400 calls; the first batch must be evicted

      expect(sleeper.calls).to eq([])
      expect(limiter.sleep_count).to eq(0)
    end
  end

  describe "#backoff_429" do
    it "returns the block's value when it does not raise" do
      limiter = described_class.new(sleeper: FakeSleeper.new, clock: FakeClock.new(Time.utc(2026, 1, 1)))

      result = limiter.backoff_429 { "ok" }

      expect(result).to eq("ok")
    end

    it "retries on UmApi::RateLimited until the block succeeds, sleeping once per retry" do
      sleeper = FakeSleeper.new
      limiter = described_class.new(sleeper: sleeper, clock: FakeClock.new(Time.utc(2026, 1, 1)))
      attempts = 0

      result = limiter.backoff_429 do
        attempts += 1
        raise UmApi::RateLimited, "429" if attempts <= 3
        "ok after #{attempts} attempts"
      end

      expect(result).to eq("ok after 4 attempts")
      expect(sleeper.calls).to eq([ 61, 61, 61 ])
      expect(limiter.sleep_count).to eq(3)
    end

    it "re-raises UmApi::RateLimited after 10 attempts, having slept exactly 10 times" do
      sleeper = FakeSleeper.new
      limiter = described_class.new(sleeper: sleeper, clock: FakeClock.new(Time.utc(2026, 1, 1)))
      attempts = 0

      expect do
        limiter.backoff_429 do
          attempts += 1
          raise UmApi::RateLimited, "429 forever"
        end
      end.to raise_error(UmApi::RateLimited)

      expect(attempts).to eq(11) # the initial attempt plus 10 retries
      expect(sleeper.calls).to eq(Array.new(10, 61))
      expect(limiter.sleep_count).to eq(10)
    end
  end

  describe "#sleep_count" do
    it "accumulates sleeps from both throttle! and backoff_429" do
      sleeper = FakeSleeper.new
      limiter = described_class.new(sleeper: sleeper, clock: FakeClock.new(Time.utc(2026, 1, 1)))

      401.times { limiter.throttle! } # +1 sleep

      attempts = 0
      limiter.backoff_429 do
        attempts += 1
        raise UmApi::RateLimited, "429" if attempts <= 2
        "ok"
      end # +2 sleeps

      expect(limiter.sleep_count).to eq(3)
    end
  end
end
