require "rails_helper"

# Task 12 of planning/plans/phase-2-ingestion.md: Sync::RunPipeline
# orchestrates the six phase-2 sync phases into one resumable run (spec D7).
# Every phase class here is STUBBED (`allow(phase_class).to receive(:call)`)
# rather than run for real — this suite tests the ORCHESTRATION (order,
# stop-on-failure, resume, the 61s inter-phase pause, one shared client,
# never-raises), not any individual phase's business logic, which already
# has its own spec (spec/lib/sync/update_*_spec.rb). Each stub also stamps
# the corresponding SyncPhase row itself, exactly like the real
# Sync::BasePhase#call would — the pipeline itself never touches a
# succeeded/failed phase's row, only a skipped one's (see run_pipeline.rb).
#
# No real sleeps, ever: `sleeper:` is injected as a fake that records its
# calls instead of invoking Kernel.sleep.
RSpec.describe Sync::RunPipeline do
  let(:workspace) { create(:workspace) }
  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:client) { instance_double(UmApi::Client) }

  before { Current.workspace = workspace }

  # Stubs `phase_class.call` to succeed or fail, stamping a real SyncPhase
  # row along the way (mirroring what Sync::BasePhase#call would actually
  # persist) so specs can assert on `run.sync_phases` state, not just the
  # Result. `call_log` (if given) records phase keys in call order.
  def stub_phase(phase_class, status:, call_log: nil)
    allow(phase_class).to receive(:call) do |run:, client:| # rubocop:disable Lint/UnusedBlockArgument
      call_log << phase_class::KEY if call_log
      phase = run.sync_phases.find_or_create_by!(key: phase_class::KEY) { |p| p.workspace = run.workspace }

      if status == :succeeded
        phase.update!(status: :succeeded, started_at: Time.current, finished_at: Time.current,
                       counters: { "created" => 1 })
        Result.success(counters: { "created" => 1 }, warnings: [])
      else
        phase.update!(status: :failed, started_at: Time.current, finished_at: Time.current,
                       error_messages: [ "boom" ])
        Result.failure("boom")
      end
    end
  end

  def stub_all_core_succeeding(call_log: nil)
    described_class::CORE_PHASES.each { |phase_class| stub_phase(phase_class, status: :succeeded, call_log: call_log) }
  end

  describe "the happy path — every core phase succeeds" do
    it "runs all six core phases in the fixed order, pausing 61s between each, and marks the run succeeded" do
      call_log = []
      stub_all_core_succeeding(call_log: call_log)

      run = described_class.call(sleeper: sleeper, client: client)

      expect(call_log).to eq(%w[campuses buildings rooms facility_ids characteristics contacts])
      expect(sleeps).to eq([ 61, 61, 61, 61, 61 ]) # 5 gaps between 6 phases, never after the last
      expect(run).to be_succeeded
      expect(run.finished_at).to be_present
      expect(run.sync_phases.count).to eq(6)
      expect(run.sync_phases.pluck(:status).uniq).to eq([ "succeeded" ])
    end

    it "builds and shares exactly ONE UmApi::Client across every phase call" do
      seen_clients = []
      described_class::CORE_PHASES.each do |phase_class|
        allow(phase_class).to receive(:call) do |run:, client:|
          seen_clients << client
          phase = run.sync_phases.find_or_create_by!(key: phase_class::KEY) { |p| p.workspace = run.workspace }
          phase.update!(status: :succeeded, finished_at: Time.current)
          Result.success(counters: {}, warnings: [])
        end
      end

      described_class.call(sleeper: sleeper, client: client)

      expect(seen_clients.uniq.size).to eq(1)
      expect(seen_clients.first).to equal(client)
    end

    it "defaults to a real UmApi::Client when none is injected" do
      stub_all_core_succeeding
      fake_client = instance_double(UmApi::Client)
      allow(UmApi::Client).to receive(:new).and_return(fake_client)

      described_class.call(sleeper: sleeper)

      expect(UmApi::Client).to have_received(:new).once
    end

    it "creates the run under Current.workspace with the requested dry_run flag" do
      stub_all_core_succeeding

      run = described_class.call(dry_run: true, sleeper: sleeper, client: client)

      expect(run.workspace).to eq(workspace)
      expect(run).to be_dry_run
    end
  end

  describe "stop-on-first-core-failure (Brief §6.1)" do
    it "stops at the failing phase, skips the rest, and marks the run failed — leaving a complete row for every phase" do
      call_log = []
      stub_phase(described_class::CORE_PHASES[0], status: :succeeded, call_log: call_log)
      stub_phase(described_class::CORE_PHASES[1], status: :succeeded, call_log: call_log)
      stub_phase(described_class::CORE_PHASES[2], status: :failed, call_log: call_log)
      # Phases 4-6 are never expected to receive .call at all.
      described_class::CORE_PHASES[3..].each do |phase_class|
        allow(phase_class).to receive(:call)
      end

      run = described_class.call(sleeper: sleeper, client: client)

      expect(call_log).to eq(%w[campuses buildings rooms])
      described_class::CORE_PHASES[3..].each { |phase_class| expect(phase_class).not_to have_received(:call) }

      expect(run).to be_failed
      expect(run.finished_at).to be_present

      statuses = run.sync_phases.pluck(:key, :status).to_h
      expect(statuses).to eq(
        "campuses" => "succeeded",
        "buildings" => "succeeded",
        "rooms" => "failed",
        "facility_ids" => "skipped",
        "characteristics" => "skipped",
        "contacts" => "skipped"
      )

      # Sleeps only happen between phases that actually ran: 1->2, 2->3.
      # Never after the phase that failed and stopped the run.
      expect(sleeps).to eq([ 61, 61 ])
    end
  end

  describe "resume_run: (spec D7 — resumable)" do
    it "skips already-succeeded phases and re-runs from the first non-succeeded phase onward" do
      # Simulate a prior attempt that failed at phase 3 (rooms): 1-2
      # succeeded, 3 failed, 4-6 skipped — exactly the row shapes the
      # stop-on-failure spec above produces.
      failed_run = create(:sync_run, workspace: workspace, status: :failed, dry_run: false)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "campuses", status: :succeeded)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "buildings", status: :succeeded)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "rooms", status: :failed)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "facility_ids", status: :skipped)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "characteristics", status: :skipped)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "contacts", status: :skipped)

      call_log = []
      # campuses/buildings must NOT be called again on resume.
      allow(described_class::CORE_PHASES[0]).to receive(:call)
      allow(described_class::CORE_PHASES[1]).to receive(:call)
      stub_phase(described_class::CORE_PHASES[2], status: :succeeded, call_log: call_log) # rooms
      stub_phase(described_class::CORE_PHASES[3], status: :succeeded, call_log: call_log) # facility_ids
      stub_phase(described_class::CORE_PHASES[4], status: :succeeded, call_log: call_log) # characteristics
      stub_phase(described_class::CORE_PHASES[5], status: :succeeded, call_log: call_log) # contacts

      run = described_class.call(resume_run: failed_run, sleeper: sleeper, client: client)

      expect(run).to eq(failed_run)
      expect(described_class::CORE_PHASES[0]).not_to have_received(:call)
      expect(described_class::CORE_PHASES[1]).not_to have_received(:call)
      expect(call_log).to eq(%w[rooms facility_ids characteristics contacts])

      expect(run).to be_succeeded
      expect(run.finished_at).to be_present
      statuses = run.sync_phases.pluck(:key, :status).to_h
      expect(statuses).to eq(
        "campuses" => "succeeded",
        "buildings" => "succeeded",
        "rooms" => "succeeded",
        "facility_ids" => "succeeded",
        "characteristics" => "succeeded",
        "contacts" => "succeeded"
      )
      # 3 gaps between the 4 phases actually re-run.
      expect(sleeps).to eq([ 61, 61, 61 ])
    end

    it "stops again and skips the rest if the resumed run fails again at the same phase" do
      failed_run = create(:sync_run, workspace: workspace, status: :failed)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "campuses", status: :succeeded)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "buildings", status: :succeeded)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "rooms", status: :failed)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "facility_ids", status: :skipped)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "characteristics", status: :skipped)
      create(:sync_phase, sync_run: failed_run, workspace: workspace, key: "contacts", status: :skipped)

      allow(described_class::CORE_PHASES[0]).to receive(:call)
      allow(described_class::CORE_PHASES[1]).to receive(:call)
      stub_phase(described_class::CORE_PHASES[2], status: :failed) # rooms fails again
      allow(described_class::CORE_PHASES[3]).to receive(:call)
      allow(described_class::CORE_PHASES[4]).to receive(:call)
      allow(described_class::CORE_PHASES[5]).to receive(:call)

      run = described_class.call(resume_run: failed_run, sleeper: sleeper, client: client)

      expect(run).to be_failed
      expect(described_class::CORE_PHASES[3]).not_to have_received(:call)
      statuses = run.sync_phases.pluck(:key, :status).to_h
      expect(statuses["rooms"]).to eq("failed")
      expect(statuses["facility_ids"]).to eq("skipped")
      expect(statuses["characteristics"]).to eq("skipped")
      expect(statuses["contacts"]).to eq("skipped")
    end
  end

  describe "OPTIONAL_PHASES (spec D11 — failure-isolated)" do
    # `KEY = "..."` inside a `Class.new do ... end` block binds to the
    # block's ENCLOSING lexical scope, not the new anonymous class itself —
    # constant assignment follows lexical scope, unlike the `self` receiver
    # `class_eval` otherwise rebinds. `const_set` is the correct way to give
    # an anonymous class its own constant here.
    let(:fake_optional_phase) do
      Class.new { def self.call(run:, client:); end }.tap { |klass| klass.const_set(:KEY, "availability") }
    end

    before { stub_const("Sync::RunPipeline::OPTIONAL_PHASES", [ fake_optional_phase ].freeze) }

    it "runs the optional phase after core, and its FAILURE does not change the run's success" do
      stub_all_core_succeeding
      allow(fake_optional_phase).to receive(:call) do |run:, client:| # rubocop:disable Lint/UnusedBlockArgument
        phase = run.sync_phases.find_or_create_by!(key: "availability") { |p| p.workspace = run.workspace }
        phase.update!(status: :failed, finished_at: Time.current, error_messages: [ "meetings endpoint down" ])
        Result.failure("meetings endpoint down")
      end

      run = described_class.call(sleeper: sleeper, client: client)

      expect(run).to be_succeeded # core succeeded; the optional failure must not flip this
      expect(run.sync_phases.find_by!(key: "availability")).to be_failed
    end

    it "still runs the optional phase even when core failed" do
      call_log = []
      stub_phase(described_class::CORE_PHASES[0], status: :failed, call_log: call_log)
      described_class::CORE_PHASES[1..].each { |phase_class| allow(phase_class).to receive(:call) }
      allow(fake_optional_phase).to receive(:call) do |run:, client:| # rubocop:disable Lint/UnusedBlockArgument
        call_log << "availability"
        phase = run.sync_phases.find_or_create_by!(key: "availability") { |p| p.workspace = run.workspace }
        phase.update!(status: :succeeded, finished_at: Time.current)
        Result.success(counters: {}, warnings: [])
      end

      run = described_class.call(sleeper: sleeper, client: client)

      expect(run).to be_failed # core's failure still stands
      expect(call_log).to eq(%w[campuses availability])
      expect(run.sync_phases.find_by!(key: "availability")).to be_succeeded
    end
  end

  describe "never raises out of .call" do
    it "swallows a phase class raising directly (bypassing the BasePhase Result contract) and marks the run failed" do
      stub_phase(described_class::CORE_PHASES[0], status: :succeeded)
      allow(described_class::CORE_PHASES[1]).to receive(:call).and_raise(StandardError, "phase blew up unexpectedly")
      described_class::CORE_PHASES[2..].each { |phase_class| allow(phase_class).to receive(:call) }

      run = nil
      expect { run = described_class.call(sleeper: sleeper, client: client) }.not_to raise_error

      expect(run).to be_failed
      expect(run.sync_phases.find_by!(key: "buildings")).to be_failed
      expect(run.sync_phases.find_by!(key: "buildings").error_messages).to eq([ "phase blew up unexpectedly" ])
      described_class::CORE_PHASES[2..].each { |phase_class| expect(phase_class).not_to have_received(:call) }
    end

    it "never raises even if the run row itself can't be created" do
      Current.workspace = nil # SyncRun requires a workspace; this makes create! raise

      expect { described_class.call(sleeper: sleeper, client: client) }.not_to raise_error
    end
  end
end
