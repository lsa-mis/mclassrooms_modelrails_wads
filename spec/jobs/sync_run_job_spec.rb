require "rails_helper"

# The pipeline is stubbed. The test adapter ignores limits_concurrency and never sets provider_job_id, so
# the lock is checked through its key and the dropped-request path through a job with no provider id.
RSpec.describe SyncRunJob, type: :job do
  include ActiveJob::TestHelper

  let(:workspace) { create(:workspace) }
  let(:operator) { create(:user) }

  before { allow(Sync::RunPipeline).to receive(:call) { |run:| run } }

  def failed_run(at: 1.day.ago) = create(:sync_run, workspace:, status: :failed, started_at: at, finished_at: at)

  describe "the one-sync lock" do
    it "is shared by the nightly run, Run now and Retry for a workspace, and by nothing in another workspace" do
      keys = [ described_class.new(workspace), described_class.new(workspace, requested_by: operator),
               described_class.new(workspace, resume: failed_run, requested_by: operator) ].map(&:concurrency_key)

      expect(keys.uniq.size).to eq(1)
      expect(described_class.new(create(:workspace)).concurrency_key).not_to eq(keys.first)
      expect(described_class.concurrency_limit).to eq(1)
      expect(described_class.concurrency_on_conflict).to eq(:discard)
    end
  end

  describe ".request" do
    def job_with(provider_job_id) = described_class.new(workspace).tap { |job| job.provider_job_id = provider_job_id }

    it "reports a stored job as queued" do
      allow(described_class).to receive(:perform_later).and_return(job_with("42"))

      expect(described_class.request(workspace, requested_by: operator)).to eq(:queued)
      expect(described_class).to have_received(:perform_later).with(workspace, requested_by: operator)
    end

    it "reports a job Solid Queue dropped, which comes back without a provider id, as already running" do
      allow(described_class).to receive(:perform_later).and_return(job_with(nil))

      expect(described_class.request(workspace)).to eq(:already_running)
    end

    it "reports a failed enqueue as not queued" do
      allow(described_class).to receive(:perform_later).and_return(false)

      expect(described_class.request(workspace)).to eq(:not_queued)
    end
  end

  describe "#perform" do
    it "starts a new run, audits who asked for it, and hands it to the pipeline" do
      described_class.perform_now(workspace, requested_by: operator)

      run = SyncRun.where(workspace:).sole
      expect(run).to have_attributes(status: "running", started_at: be_present, dry_run: false)
      expect(Sync::RunPipeline).to have_received(:call).with(run:)
      expect(ActivityLog.find_by!(action: "sync_run.requested", trackable: run)).to have_attributes(actor: operator, workspace:)
    end

    it "starts a dry run when the environment asks for one" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("API_UPDATE_DELETE_DRY_RUN").and_return("1")

      described_class.perform_now(workspace)

      expect(SyncRun.where(workspace:).sole).to be_dry_run
    end

    it "writes no audit row for the nightly run, which nobody requested" do
      described_class.perform_now(workspace)

      expect(ActivityLog.where("action LIKE 'sync_run.%'")).to be_empty
    end

    it "fails a run a stopped worker left running, then starts the new one" do
      abandoned = create(:sync_run, workspace:, status: :running, started_at: 2.hours.ago)

      described_class.perform_now(workspace, requested_by: operator)

      expect(abandoned.reload).to be_failed
      expect(SyncRun.where(workspace:).running.where.not(id: abandoned.id)).to exist
    end

    it "retries the most recent failed run and audits the retry" do
      failed = failed_run

      described_class.perform_now(workspace, resume: failed, requested_by: operator)

      expect(Sync::RunPipeline).to have_received(:call).with(run: failed)
      expect(ActivityLog.find_by!(action: "sync_run.resumed", trackable: failed).actor).to eq(operator)
    end

    it "does nothing for a retry of a run that is not the most recent, or did not fail" do
      older = failed_run(at: 2.days.ago)
      failed_run(at: 1.day.ago)
      succeeded = create(:sync_run, workspace:, status: :succeeded, started_at: 1.hour.ago, finished_at: 1.hour.ago)

      described_class.perform_now(workspace, resume: older, requested_by: operator)
      described_class.perform_now(workspace, resume: succeeded, requested_by: operator)

      expect(Sync::RunPipeline).not_to have_received(:call)
    end

    it "retries a most recent run a stopped worker left running" do
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
end
