require "rails_helper"

# Task 6 of planning/plans/phase-2-ingestion.md: Sync::BasePhase is the
# template-method base every concrete phase (Tasks 7+) subclasses — it owns
# finding/creating the run's SyncPhase row, timing, status transitions,
# counter/warning persistence, and turning any raised error into a
# Result.failure without ever letting it escape `.call` (the pipeline,
# Task 12, relies on that guarantee to keep running the remaining phases).
#
# BasePhase is exercised here through tiny TEST SUBCLASSES rather than any
# real phase (Sync::UpdateCampuses etc. don't exist yet) — each subclass
# pins one behavior (succeed, raise a typed gateway error, raise an
# unexpected error, dry-run guarded_write) via a `#perform` this file
# controls completely.
#
# FakeClient/FakeRateLimiter stand in for UmApi::Client/UmApi::RateLimiter
# — same spirit as client_spec.rb's ThrottleSpy and rate_limiter_spec.rb's
# FakeSleeper/FakeClock: minimal fakes that let a test subclass's #perform
# simulate "this phase made N HTTP calls / triggered N throttle sleeps"
# without any real network access or real sleeping, so BasePhase's
# before/after delta capture can be asserted precisely.
class FakeRateLimiter
  attr_accessor :sleep_count

  # `sleep_count:` seedable so a spec can simulate a shared limiter a PRIOR
  # phase already slept on — the delta-nonzero regression test starts above
  # zero on purpose.
  def initialize(sleep_count: 0)
    @sleep_count = sleep_count
  end
end

class FakeClient
  attr_reader :call_count, :rate_limiter

  # `call_count:`/`rate_limiter:` seedable for the same reason — a client
  # carried across phases starts each new phase at a non-zero cumulative
  # count, and BasePhase must record only THIS phase's delta.
  def initialize(call_count: 0, rate_limiter: FakeRateLimiter.new)
    @call_count = call_count
    @rate_limiter = rate_limiter
  end

  # Simulates the client having sent `n` HTTP requests, exactly like
  # UmApi::Client#call_count incrementing once per request actually sent.
  def simulate_calls(n)
    @call_count += n
  end
end

class SucceedingTestPhase < Sync::BasePhase
  KEY = "campuses"

  private

  def perform
    count(:created, 3)
    count(:updated, 1)
    add_warning("slow page")
    client.simulate_calls(2)
    client.rate_limiter.sleep_count += 1
  end
end

class RaisingUmApiTestPhase < Sync::BasePhase
  KEY = "buildings"

  private

  def perform
    count(:created, 1)
    add_warning("partial page before failure")
    client.simulate_calls(1)
    raise UmApi::ServerError, "gateway exploded"
  end
end

class RaisingStandardErrorTestPhase < Sync::BasePhase
  KEY = "rooms"

  private

  def perform
    count(:created, 1)
    raise "unexpected boom"
  end
end

class GuardedWriteTestPhase < Sync::BasePhase
  KEY = "facility_ids"

  def initialize(run:, client:)
    super
    @write_executed = false
  end

  def write_executed? = @write_executed

  private

  def perform
    count(:deactivated, 2)
    guarded_write { @write_executed = true }
  end
end

RSpec.describe Sync::BasePhase do
  describe "a succeeding subclass" do
    it "records a succeeded phase with timing, merged counters, warnings, and api_calls/rate_limit_sleeps deltas" do
      run = create(:sync_run)
      client = FakeClient.new

      result = SucceedingTestPhase.call(run: run, client: client)

      phase = run.sync_phases.find_by!(key: "campuses")
      expect(phase).to be_succeeded
      expect(phase.started_at).to be_present
      expect(phase.finished_at).to be_present
      expect(phase.duration_seconds).to be_a(Numeric).and be >= 0
      expect(phase.counters).to eq(
        "created" => 3, "updated" => 1, "api_calls" => 2, "rate_limit_sleeps" => 1
      )
      expect(phase.warnings).to eq([ "slow page" ])
      expect(phase.error_messages).to eq([])

      expect(result).to be_success
      expect(result.payload[:counters]).to eq(phase.counters)
      expect(result.payload[:warnings]).to eq([ "slow page" ])
    end

    it "reuses the existing SyncPhase row across repeated calls for the same run/key" do
      run = create(:sync_run)
      client = FakeClient.new

      SucceedingTestPhase.call(run: run, client: client)

      expect { SucceedingTestPhase.call(run: run, client: client) }
        .not_to change { SyncPhase.where(sync_run: run, key: "campuses").count }
    end

    # Teeth-test for the crux behavior: api_calls/rate_limit_sleeps must be the
    # DELTA this phase produced, not the client's absolute cumulative totals.
    # A shared client carried across a multi-phase pipeline run arrives here
    # already at call_count 5 / sleep_count 3 from prior phases; this phase
    # itself makes 2 calls / 1 sleep, so the row must record 2 / 1 — NOT 7 / 4.
    # A regression that dropped the before/after diffing (recording
    # client.call_count absolutely) would pass every other spec here — they
    # all start the fake at zero — but MUST fail this one.
    it "records only the calls/sleeps its own #perform produced, not the shared client's running totals" do
      run = create(:sync_run)
      client = FakeClient.new(call_count: 5, rate_limiter: FakeRateLimiter.new(sleep_count: 3))

      SucceedingTestPhase.call(run: run, client: client)

      phase = run.sync_phases.find_by!(key: "campuses")
      expect(phase.counters["api_calls"]).to eq(2)
      expect(phase.counters["rate_limit_sleeps"]).to eq(1)
      # Sanity: the shared client did advance to its new cumulative totals.
      expect(client.call_count).to eq(7)
      expect(client.rate_limiter.sleep_count).to eq(4)
    end
  end

  describe "a subclass raising UmApi::Error" do
    it "records a failed phase with the error message and returns Result.failure without propagating" do
      run = create(:sync_run)
      client = FakeClient.new
      result = nil

      expect { result = RaisingUmApiTestPhase.call(run: run, client: client) }.not_to raise_error

      phase = run.sync_phases.find_by!(key: "buildings")
      expect(phase).to be_failed
      expect(phase.started_at).to be_present
      expect(phase.finished_at).to be_present
      expect(phase.error_messages).to eq([ "gateway exploded" ])
      expect(phase.counters).to eq("created" => 1, "api_calls" => 1, "rate_limit_sleeps" => 0)
      expect(phase.warnings).to eq([ "partial page before failure" ])

      expect(result).not_to be_success
      expect(result.errors).to eq([ "gateway exploded" ])
      expect(result.payload[:counters]).to eq(phase.counters)
      # MINOR 3: the failure Result carries warnings just like success does,
      # so a caller reading result.payload[:warnings] never gets nil.
      expect(result.payload[:warnings]).to eq([ "partial page before failure" ])
    end
  end

  describe "a subclass raising an unexpected StandardError" do
    it "records a failed phase and returns Result.failure without propagating" do
      run = create(:sync_run)
      client = FakeClient.new
      result = nil

      expect { result = RaisingStandardErrorTestPhase.call(run: run, client: client) }.not_to raise_error

      phase = run.sync_phases.find_by!(key: "rooms")
      expect(phase).to be_failed
      expect(phase.error_messages).to eq([ "unexpected boom" ])
      expect(phase.counters["created"]).to eq(1)

      expect(result).not_to be_success
      expect(result.errors).to eq([ "unexpected boom" ])
    end
  end

  # IMPORTANT 2: the "nothing escapes .call" invariant Task 12's pipeline
  # depends on must hold even when the failure originates in the SyncPhase
  # find-or-create / running-stamp itself (e.g. a RecordNotUnique racing the
  # unique (sync_run_id, key) index, or a validation failure), not just
  # inside #perform. Stubbing SyncPhase#update! to raise reproduces a
  # running-stamp failure: .call must still return Result.failure and must
  # not propagate.
  describe "a failure during phase creation / running-stamp" do
    it "returns Result.failure without propagating when the running-stamp raises" do
      run = create(:sync_run)
      client = FakeClient.new
      allow_any_instance_of(SyncPhase).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(SyncPhase.new))
      result = nil

      expect { result = SucceedingTestPhase.call(run: run, client: client) }.not_to raise_error

      expect(result).not_to be_success
      expect(result.errors).not_to be_empty
    end
  end

  describe "#dry_run?" do
    it "delegates to run.dry_run?" do
      dry_phase = GuardedWriteTestPhase.new(run: build_stubbed(:sync_run, dry_run: true), client: FakeClient.new)
      live_phase = GuardedWriteTestPhase.new(run: build_stubbed(:sync_run, dry_run: false), client: FakeClient.new)

      expect(dry_phase.dry_run?).to be true
      expect(live_phase.dry_run?).to be false
    end
  end

  describe "#guarded_write" do
    it "counts without executing the block under dry-run" do
      run = create(:sync_run, dry_run: true)
      client = FakeClient.new
      phase_instance = GuardedWriteTestPhase.new(run: run, client: client)

      result = phase_instance.call

      expect(phase_instance.write_executed?).to be false
      expect(result.payload[:counters]["deactivated"]).to eq(2)

      phase = run.sync_phases.find_by!(key: "facility_ids")
      expect(phase.counters["deactivated"]).to eq(2)
    end

    it "executes the block normally when the run is not a dry run" do
      run = create(:sync_run, dry_run: false)
      client = FakeClient.new
      phase_instance = GuardedWriteTestPhase.new(run: run, client: client)

      phase_instance.call

      expect(phase_instance.write_executed?).to be true
    end
  end
end
