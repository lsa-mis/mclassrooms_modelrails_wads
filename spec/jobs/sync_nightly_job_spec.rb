require "rails_helper"

# Task 12 of planning/plans/phase-2-ingestion.md: SyncNightlyJob is the
# Solid Queue recurring-task trigger (config/recurring.yml: nightly_sync,
# 2:30am America/Detroit — spec D7's "Scheduling via Solid Queue recurring
# tasks, not host cron"). Sync::RunPipeline.call is stubbed throughout —
# this spec exercises only the job's OWN two responsibilities: resolving
# and setting Current.workspace (mirrors DirectoryScoped's
# TenancyConfig.shared_workspace_slug lookup — see
# app/controllers/concerns/directory_scoped.rb and its spec for the same
# stubbing pattern), and never raising even when the pipeline records a
# failed run.
RSpec.describe SyncNightlyJob, type: :job do
  let(:shared_workspace) { create(:workspace, slug: "shared-sync-test", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(shared_workspace.slug)
  end

  it "sets Current.workspace to the shared workspace before calling the pipeline" do
    seen_workspace = nil
    allow(Sync::RunPipeline).to receive(:call) do
      seen_workspace = Current.workspace
      build_stubbed(:sync_run, workspace: shared_workspace)
    end

    described_class.new.perform

    expect(seen_workspace).to eq(shared_workspace)
  end

  it "delegates to Sync::RunPipeline.call" do
    run = build_stubbed(:sync_run, workspace: shared_workspace)
    allow(Sync::RunPipeline).to receive(:call).and_return(run)

    described_class.new.perform

    expect(Sync::RunPipeline).to have_received(:call)
  end

  it "does not raise even when the pipeline returns a failed run" do
    failed_run = create(:sync_run, workspace: shared_workspace, status: :failed, finished_at: Time.current)
    allow(Sync::RunPipeline).to receive(:call).and_return(failed_run)

    expect { described_class.new.perform }.not_to raise_error
  end
end
