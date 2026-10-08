require "rails_helper"

# Runs the pipeline for a run an operator queued or retried; the pipeline itself is stubbed.
RSpec.describe SyncRunJob, type: :job do
  let(:workspace) { create(:workspace) }
  let(:run) { create(:sync_run, workspace:, status: :running, started_at: nil, attempt: 2) }

  before { allow(Sync::RunPipeline).to receive(:call) { |resume_run:| resume_run } }

  it "claims the run, sets its workspace, and hands it to the pipeline" do
    seen = nil
    allow(Sync::RunPipeline).to receive(:call) do |resume_run:|
      seen = [ Current.workspace, resume_run, resume_run.started_at.present? ]
      resume_run
    end

    described_class.perform_now(run, 2)

    expect(seen).to eq([ workspace, run, true ])
  end

  it "turns away a job for an attempt a retry has superseded" do
    described_class.perform_now(run, 1)

    expect(Sync::RunPipeline).not_to have_received(:call)
    expect(run.reload.started_at).to be_nil
  end

  it "runs a duplicate delivery of the same attempt only once" do
    described_class.perform_now(run, 2)
    described_class.perform_now(run, 2)

    expect(Sync::RunPipeline).to have_received(:call).once
  end
end
