require "rails_helper"

RSpec.describe SyncRun, type: :model do
  let(:record) { create(:sync_run) }

  it_behaves_like "a tenanted directory record"

  describe "status enum" do
    it "defaults to running" do
      run = SyncRun.create!(workspace: create(:workspace))
      expect(run.status).to eq("running")
      expect(run.running?).to be true
    end

    it "supports succeeded" do
      run = build(:sync_run, status: "succeeded")
      expect(run.succeeded?).to be true
    end

    it "supports failed" do
      run = build(:sync_run, status: "failed")
      expect(run.failed?).to be true
    end

    it "raises ArgumentError for an unknown status" do
      run = build(:sync_run)
      expect { run.status = "bogus" }.to raise_error(ArgumentError)
    end
  end

  describe "dry_run" do
    it "defaults to false" do
      run = SyncRun.create!(workspace: create(:workspace))
      expect(run.dry_run).to eq(false)
    end

    it "can be set to true" do
      run = build(:sync_run, dry_run: true)
      expect(run.dry_run).to eq(true)
    end
  end

  describe "#sync_phases" do
    it "has many sync_phases" do
      run = create(:sync_run)
      phase = create(:sync_phase, sync_run: run, workspace: run.workspace)

      expect(run.sync_phases).to include(phase)
    end

    it "destroys dependent sync_phases when the run is destroyed" do
      run = create(:sync_run)
      create(:sync_phase, sync_run: run, workspace: run.workspace)

      expect { run.destroy }.to change(SyncPhase, :count).by(-1)
    end
  end

  describe ".latest" do
    it "returns the most recently started run" do
      workspace = create(:workspace)
      create(:sync_run, workspace: workspace, started_at: 2.days.ago)
      newer = create(:sync_run, workspace: workspace, started_at: 1.hour.ago)

      expect(SyncRun.latest).to eq(newer)
    end

    it "falls back to created_at when started_at is nil" do
      workspace = create(:workspace)
      create(:sync_run, workspace: workspace, started_at: nil)
      second_run = create(:sync_run, workspace: workspace, started_at: nil)

      expect(SyncRun.latest).to eq(second_run)
    end

    it "returns nil when there are no runs" do
      expect(SyncRun.latest).to be_nil
    end
  end
end
