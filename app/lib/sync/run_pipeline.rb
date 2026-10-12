# Runs the sync phases, in order, for one SyncRun and never raises once that run exists. Phases, resuming,
# the 61s pause, and the one-sync-at-a-time rule: app/docs/developer/sync.md.
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

    def self.call(dry_run: SyncRun.dry_run_by_default?, run: nil,
                  sleeper: ->(seconds) { Kernel.sleep(seconds) }, client: nil,
                  operator_log: Sync::OperatorLog.new)
      new(dry_run: dry_run, run: run, sleeper: sleeper, client: client,
          operator_log: operator_log).call
    end

    def initialize(dry_run:, run:, sleeper:, client:, operator_log:)
      @dry_run = dry_run
      @given_run = run
      @sleeper = sleeper
      @client = client || UmApi::Client.new
      @operator_log = operator_log
    end

    def call
      # Creating the run sits outside the never-raises boundary: with no row there is nowhere to record a failure.
      run = @given_run || create_run!
      execute(run)
      run
    end

    private

    attr_reader :dry_run, :sleeper, :client, :operator_log

    # The never-raises boundary: `run` is guaranteed to exist here, so any
    # failure below is recorded on it and swallowed rather than propagated.
    def execute(run)
      # A given run may be a failed one being resumed; this attempt gets its own start time.
      run.update!(status: :running, finished_at: nil, started_at: Time.current) if @given_run

      execute_core_phases(run)
      execute_optional_phases(run)
      run.update!(finished_at: Time.current)
    rescue StandardError => e
      # NOT a phase failure (those are contained in #run_phase) — the
      # pipeline's own bookkeeping broke. Best-effort mark the run failed so
      # a nightly job never raises once a run exists; `run` is non-nil by
      # construction of #call.
      operator_log.error("Sync::RunPipeline: unexpected pipeline error: #{e.class}: #{e.message}")
      begin
        run.update!(status: :failed, finished_at: Time.current)
      rescue StandardError => stamp_error
        operator_log.error(
          "Sync::RunPipeline: failed to stamp run failed after pipeline error: " \
          "#{stamp_error.class}: #{stamp_error.message}"
        )
      end
    end

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
      operator_log.error("Sync::RunPipeline: failed to stamp phase failed: #{e.class}: #{e.message}")
    end

    def find_or_create_phase!(run, phase_class)
      run.sync_phases.find_or_create_by!(key: phase_class::KEY) { |phase| phase.workspace = run.workspace }
    end
  end
end
