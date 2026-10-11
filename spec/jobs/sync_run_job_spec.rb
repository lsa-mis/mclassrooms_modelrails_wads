require "rails_helper"

# The pipeline is stubbed. The one-at-a-time guarantee is Solid Queue's limits_concurrency, which the
# test adapter does not enforce, so these examples check the declaration, not the semaphore.
RSpec.describe SyncRunJob, type: :job do
  let(:workspace) { create(:workspace) }
  let(:operator) { create(:user) }

  before { allow(Sync::RunPipeline).to receive(:call) { |run:| run } }

  it "allows one sync per workspace at a time, and drops a request made while one runs" do
    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.concurrency_on_conflict).to eq(:discard)
    expect(described_class.concurrency_duration).to eq(described_class::DURATION)
    expect(described_class.new(workspace, requested_by: operator).concurrency_key).to eq("SyncRunJob/Workspace/#{workspace.id}")
    expect(described_class.new(workspace).concurrency_key).not_to eq(described_class.new(create(:workspace)).concurrency_key)
  end

  it "starts a new run, audits who asked for it, and hands it to the pipeline" do
    described_class.perform_now(workspace, requested_by: operator)

    run = SyncRun.where(workspace:).sole
    expect(run).to have_attributes(status: "running", started_at: be_present)
    expect(Sync::RunPipeline).to have_received(:call).with(run: run)
    expect(ActivityLog.find_by!(action: "sync_run.requested", trackable: run)).to have_attributes(actor: operator, workspace:)
  end

  it "writes no audit row for the nightly run, which nobody requested" do
    described_class.perform_now(workspace)

    expect(ActivityLog.where("action LIKE 'sync_run.%'")).to be_empty
  end

  it "retries a failed run and audits the retry" do
    failed = create(:sync_run, workspace:, status: :failed, started_at: 1.day.ago, finished_at: 1.day.ago)

    described_class.perform_now(workspace, resume: failed, requested_by: operator)

    expect(Sync::RunPipeline).to have_received(:call).with(run: failed)
    expect(ActivityLog.find_by!(action: "sync_run.resumed", trackable: failed).actor).to eq(operator)
  end

  it "does nothing for a retry of a run that is no longer failed" do
    succeeded = create(:sync_run, workspace:, status: :succeeded, started_at: 1.day.ago, finished_at: 1.day.ago)

    described_class.perform_now(workspace, resume: succeeded, requested_by: operator)

    expect(Sync::RunPipeline).not_to have_received(:call)
  end

  it "fails a run a stopped worker left running before starting, so it can be retried" do
    abandoned = create(:sync_run, workspace:, status: :running, started_at: 2.hours.ago)

    described_class.perform_now(workspace, resume: abandoned, requested_by: operator)

    expect(Sync::RunPipeline).to have_received(:call).with(run: abandoned)
  end

  it "sets the workspace the pipeline and audit read" do
    seen = nil
    allow(Sync::RunPipeline).to receive(:call) { |run:| seen = Current.workspace; run }

    described_class.perform_now(workspace)

    expect(seen).to eq(workspace)
  end
end
