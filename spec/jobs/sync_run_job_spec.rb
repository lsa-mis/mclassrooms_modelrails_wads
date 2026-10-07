require "rails_helper"

# Runs the pipeline for a run an operator queued or retried; the pipeline itself is stubbed.
RSpec.describe SyncRunJob, type: :job do
  let(:workspace) { create(:workspace) }
  let(:run) { create(:sync_run, workspace:, status: :running) }

  it "sets the run's workspace and hands the run to the pipeline" do
    seen = nil
    allow(Sync::RunPipeline).to receive(:call) do |resume_run:|
      seen = [ Current.workspace, resume_run ]
      resume_run
    end

    described_class.perform_now(run)

    expect(seen).to eq([ workspace, run ])
  end
end
