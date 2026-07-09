# Orchestrator tying together the six phase-2 sync phases (Task 12 of
# planning/plans/phase-2-ingestion.md; roadmap Lib section; Brief §6.1; spec
# D7). Every phase (Sync::UpdateCampuses .. Sync::UpdateContacts, Tasks 7-11)
# is a Sync::BasePhase subclass whose `.call(run:, client:)` NEVER raises —
# this class is the one thing standing between that per-phase guarantee and
# a fully automated nightly run, so its OWN bookkeeping (creating/finding the
# run row, deciding what to skip, timing) must uphold the same invariant.
#
# CORE_PHASES / OPTIONAL_PHASES (spec D11): CORE_PHASES runs in the fixed
# Brief §6.1 order with stop-on-first-failure — a broken phase 3 means
# phases 4-6 never see live data this run, so they're stamped `skipped`
# rather than left `pending` (indistinguishable from "never scheduled").
# OPTIONAL_PHASES starts empty; phase 6 (availability) appends
# Sync::UpdateAvailability here. Optional phases are failure-isolated: each
# runs independently of the others AND of core's outcome (they always run,
# even after a core failure — an availability refresh is still worth
# attempting even if, say, the characteristics phase choked), and a failed
# optional phase only fails its own SyncPhase row, never `run.status`.
#
# Resumability (spec D7): passing `resume_run:` reuses that SyncRun instead
# of creating a new one, skipping every phase already `succeeded` on it and
# re-running everything else (`failed`, `skipped`, or `pending`) — a run
# that stopped at phase 3 resumes by re-running 3-6; phases 1-2 are
# untouched. This requires no special-casing beyond "skip succeeded keys":
# Sync::BasePhase#find_or_create_phase! already reuses the existing
# SyncPhase row for a re-run key and flips its status forward from
# whatever it was.
#
# One client per run: `client:` (real usage) or the pipeline's own
# `UmApi::Client.new` (default) is built exactly once and threaded through
# every phase call — core AND optional — so BasePhase's before/after
# api_calls/rate_limit_sleeps delta capture (Task 6) reflects one shared
# client's running totals, not N independent ones.
#
# The 61s inter-phase pause (Brief §6.1: 400 calls/min self-imposed budget)
# is injectable via `sleeper:` (default `Kernel.sleep`) so specs never
# really sleep. It only fires BETWEEN two phases this invocation actually
# executes (never after the last phase run, never after a phase that just
# failed and stopped the run) — a resumed run's N pauses cover only the N-1
# gaps between the phases it re-runs, not the ones it skipped via
# already-succeeded.
#
# Never raises: mirrors Sync::BasePhase's invariant one level up. A real
# phase's `.call` already can't raise (Task 6), so the only things that
# could blow up `.call` here are this class's own bookkeeping (run/phase
# row writes) or — in principle, e.g. a future non-BasePhase phase class —
# a phase itself raising instead of returning a Result. `#run_phase` guards
# the latter; the top-level rescue guards the former. Either way `.call`
# returns the SyncRun, never an exception.
module Sync
  class RunPipeline
    CORE_PHASES = [
      UpdateCampuses,
      UpdateBuildings,
      UpdateRooms,
      UpdateFacilityIds,
      UpdateCharacteristics,
      UpdateContacts
    ].freeze

    OPTIONAL_PHASES = [].freeze

    PHASE_PAUSE_SECONDS = 61

    def self.call(dry_run: ENV["API_UPDATE_DELETE_DRY_RUN"].present?, resume_run: nil,
                  sleeper: ->(seconds) { Kernel.sleep(seconds) }, client: nil)
      new(dry_run: dry_run, resume_run: resume_run, sleeper: sleeper, client: client).call
    end

    def initialize(dry_run:, resume_run:, sleeper:, client:)
      @dry_run = dry_run
      @resume_run = resume_run
      @sleeper = sleeper
      @client = client || UmApi::Client.new
      @operator_log = Sync::OperatorLog.new
    end

    def call
      run = @resume_run || create_run!
      # A resumed run's prior attempt left status: failed, finished_at: set
      # — flip it back to a live "in progress" row for the duration of this
      # attempt; the final update below (success or failure) sets both again.
      run.update!(status: :running, finished_at: nil) if @resume_run

      execute_core_phases(run)
      execute_optional_phases(run)
      run.update!(finished_at: Time.current)

      run
    rescue StandardError => e
      # This is NOT a phase failure (those are contained above) — it means
      # the pipeline's own bookkeeping broke (e.g. the run row itself failed
      # validation). Best-effort mark the run failed so a nightly job never
      # raises regardless of where things went wrong; `run` may still be nil
      # if even `create_run!` couldn't produce a row.
      @operator_log.error("Sync::RunPipeline: unexpected pipeline error: #{e.class}: #{e.message}")
      begin
        run&.update!(status: :failed, finished_at: Time.current)
      rescue StandardError => stamp_error
        @operator_log.error(
          "Sync::RunPipeline: failed to stamp run failed after pipeline error: " \
          "#{stamp_error.class}: #{stamp_error.message}"
        )
      end
      run
    end

    private

    attr_reader :dry_run, :sleeper, :client, :operator_log

    def create_run!
      SyncRun.create!(workspace: Current.workspace, dry_run: dry_run, status: :running, started_at: Time.current)
    end

    def execute_core_phases(run)
      already_succeeded = run.sync_phases.succeeded.pluck(:key)
      phases_to_run = CORE_PHASES.reject { |phase_class| already_succeeded.include?(phase_class::KEY) }

      failed = false
      phases_to_run.each_with_index do |phase_class, index|
        if failed
          mark_skipped!(run, phase_class)
          next
        end

        result = run_phase(run, phase_class)

        if result.success?
          sleeper.call(PHASE_PAUSE_SECONDS) unless index == phases_to_run.length - 1
        else
          failed = true
        end
      end

      run.update!(status: failed ? :failed : :succeeded)
    end

    # Runs AFTER core regardless of whether core succeeded or stopped early
    # (spec D11: failure-isolated) — each optional phase's own success/
    # failure is independent of the others' and never touches run.status.
    def execute_optional_phases(run)
      OPTIONAL_PHASES.each { |phase_class| run_phase(run, phase_class) }
    end

    def run_phase(run, phase_class)
      operator_log.phase_started(phase_class::KEY)
      result = phase_class.call(run: run, client: client)
      operator_log.phase_finished(phase_class::KEY, result)
      result
    rescue StandardError => e
      # Defense-in-depth, not the expected path: a conforming BasePhase
      # subclass never raises out of .call (Task 6). Guards against a
      # non-conforming phase class so one bad phase still can't take down
      # the whole run — same contract as a normal Result.failure, just
      # arrived at from a different direction.
      operator_log.phase_errored(phase_class::KEY, e)
      stamp_phase_failed!(run, phase_class, e)
      Result.failure(e.message)
    end

    def mark_skipped!(run, phase_class)
      phase = find_or_create_phase!(run, phase_class)
      phase.update!(status: :skipped, finished_at: Time.current)
      operator_log.phase_skipped(phase_class::KEY)
    end

    def stamp_phase_failed!(run, phase_class, error)
      phase = find_or_create_phase!(run, phase_class)
      phase.update!(status: :failed, finished_at: Time.current, error_messages: [ error.message ])
    rescue StandardError => e
      @operator_log.error("Sync::RunPipeline: failed to stamp phase failed: #{e.class}: #{e.message}")
    end

    def find_or_create_phase!(run, phase_class)
      run.sync_phases.find_or_create_by!(key: phase_class::KEY) { |phase| phase.workspace = run.workspace }
    end
  end
end
