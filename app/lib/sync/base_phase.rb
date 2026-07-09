# Template-method base class for the six phase-2 sync phases (Task 6 of
# planning/plans/phase-2-ingestion.md; roadmap Lib section). Each concrete
# phase (Sync::UpdateCampuses, Sync::UpdateBuildings, ... — Tasks 7+) sets
# `KEY` to one of SyncPhase::KEYS and implements `#perform`, the actual sync
# work against `client`. Everything else — finding/creating the run's
# SyncPhase row, timing, status transitions, counter/warning persistence,
# and turning any raised error into a Result.failure without ever letting it
# escape `.call` — lives here exactly once.
#
# `.call(run:, client:)` is the one fixed entry point every phase (and the
# phase-2 pipeline orchestrator, Task 12) uses; subclasses are never
# instantiated by callers directly.
#
# Counters: `count(:created)` / `count(:created, n)` increments the
# phase's running counters hash (string keys, so a subclass's `count(:x)`
# and the persisted JSON column agree without a serialization step).
# `api_calls` and `rate_limit_sleeps` are computed by BasePhase itself, as
# before/after deltas straddling the `#perform` call — never by the
# subclass calling `#count` — so a phase's counters only ever reflect
# requests THAT PHASE made, not the cumulative total across a multi-phase
# pipeline run sharing one client. `client.call_count` is public
# (UmApi::Client, Task 5); `client.rate_limiter` is a matching one-line
# addition to that same class (this task) so `#rate_limiter_sleep_count`
# can read `.sleep_count` off it the same way. That helper tolerates a
# client that doesn't expose `rate_limiter` at all (returns 0 for the sleep
# delta), so a minimal test double only has to fake what it actually
# exercises.
#
# Dry-run: `#dry_run?` delegates to `run.dry_run?`. `guarded_write { }`
# skips executing the block entirely under dry-run and runs it normally
# otherwise — subclasses wrap only the destructive write itself
# (deactivation/deletion) in the block, and call `#count` separately (before
# or after `guarded_write`, not inside it), so a dry-run phase still reports
# accurate "would have" counts even though no UPDATE/DELETE ever fires.
module Sync
  class BasePhase
    def self.call(run:, client:)
      new(run: run, client: client).call
    end

    def initialize(run:, client:)
      @run = run
      @client = client
      @counters = Hash.new(0)
      @warnings = []
    end

    def call
      # The rescue wraps the ENTIRE body — phase find-or-create, the running
      # stamp, AND #perform — because Task 12's pipeline relies on .call NEVER
      # propagating: a RecordNotUnique racing the unique (sync_run_id, key)
      # index, or a validation failure on the running stamp, must become a
      # Result.failure just like a #perform blow-up, not escape and abort the
      # whole run. `phase`/`calls_before`/`sleeps_before` are nil until their
      # assignments are reached, so the rescue reads them defensively.
      phase = nil
      calls_before = nil
      sleeps_before = nil

      begin
        phase = find_or_create_phase!
        phase.update!(status: :running, started_at: Time.current, finished_at: nil, error_messages: [])

        calls_before = client.call_count
        sleeps_before = rate_limiter_sleep_count

        perform
        record_call_deltas!(calls_before, sleeps_before)

        phase.update!(status: :succeeded, finished_at: Time.current, counters: counters, warnings: warnings)
        Result.success(counters: counters.dup, warnings: warnings.dup)
      rescue StandardError => e
        # UmApi::Error (Task 5's typed gateway errors) is itself a
        # StandardError subclass, so one rescue clause handles both "the
        # gateway told us something went wrong" and "something blew up
        # unexpectedly" identically — the pipeline treats both the same way:
        # fail this phase, keep whatever it counted so far, never propagate.
        record_call_deltas!(calls_before, sleeps_before) if calls_before
        stamp_failed(phase, e)
        # error_class: carries the ORIGINAL exception's class name forward in
        # the failure Result so downstream callers (Task 12's pipeline +
        # Sync::OperatorLog) can map error class -> operator guidance by class
        # rather than re-parsing e.message. Different gateway paths word the
        # same failure differently (UmApi::Client "U-M gateway returned 401
        # ..." vs UmApi::TokenCache "token endpoint returned 401 for scope
        # ..."), so the class is the reliable key; the message is not.
        Result.failure(e.message, error_class: e.class.name, counters: counters.dup, warnings: warnings.dup)
      end
    end

    def dry_run?
      @run.dry_run?
    end

    def guarded_write
      return if dry_run?

      yield
    end

    private

    attr_reader :client, :counters, :warnings

    def count(key, n = 1)
      counters[key.to_s] += n
    end

    def add_warning(message)
      warnings << message
    end

    def perform
      raise NotImplementedError, "#{self.class} must implement #perform"
    end

    def find_or_create_phase!
      @run.sync_phases.find_or_create_by!(key: self.class::KEY) do |phase|
        phase.workspace = @run.workspace
      end
    end

    # Best-effort failure stamp: only possible if we actually got a phase row
    # back (a raise inside find_or_create_phase! leaves `phase` nil, so there
    # is nothing to stamp — the Result.failure still carries the message).
    # If the stamp itself raises (e.g. the phase row is the very thing that's
    # broken), swallow it so THAT doesn't escape .call either — the
    # never-propagate invariant wins over a perfectly-recorded failure row.
    def stamp_failed(phase, error)
      return unless phase

      phase.update!(
        status: :failed, finished_at: Time.current,
        counters: counters, warnings: warnings, error_messages: [ error.message ]
      )
    rescue StandardError => e
      Rails.logger.warn("Sync::BasePhase failed to stamp phase failed: #{e.class}: #{e.message}")
    end

    def record_call_deltas!(calls_before, sleeps_before)
      count(:api_calls, client.call_count - calls_before)
      count(:rate_limit_sleeps, rate_limiter_sleep_count - sleeps_before)
    end

    def rate_limiter_sleep_count
      return 0 unless client.respond_to?(:rate_limiter)

      # Explicit `|| 0` (not NilClass#to_i) so the nil-safety is intentional,
      # not an accident of `nil.to_i == 0`: a client whose rate_limiter is nil
      # contributes zero sleeps.
      client.rate_limiter&.sleep_count || 0
    end
  end
end
