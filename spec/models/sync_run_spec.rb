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

  describe ".history_for and .inventory_for" do
    let(:workspace) { create(:workspace) }

    it "returns the workspace's newest fourteen runs, newest first" do
      runs = 16.times.map { |i| create(:sync_run, workspace:, status: :succeeded, started_at: i.hours.ago) }
      create(:sync_run, status: :succeeded, started_at: 1.minute.ago)

      expect(described_class.history_for(workspace)).to eq(runs.first(14))
    end

    it "counts the workspace's listed buildings and rooms, and its classrooms" do
      building = create(:building, workspace:)
      create(:room, building:, workspace:, room_type: "Classroom", facility_code: "MLB1", instructional_seat_count: 30)
      create(:room, building:, workspace:, room_type: "Classroom", facility_code: "MLB2", instructional_seat_count: 30, hidden_at: Time.current)
      create(:room, building:, workspace:, room_type: "Office")
      create(:room)

      expect(described_class.inventory_for(workspace)).to include(buildings: 1, rooms: 2, classrooms: 2, listed_classrooms: 1)
    end
  end

  describe "#phases_in_order" do
    it "lists the run's phases in pipeline order" do
      run = create(:sync_run)
      %w[rooms campuses buildings].each { |key| create(:sync_phase, sync_run: run, key:) }

      expect(run.phases_in_order.map(&:key)).to eq(%w[campuses buildings rooms])
    end
  end

  describe ".fail_abandoned" do
    it "fails the workspace's runs left running, and leaves finished runs and other workspaces alone" do
      workspace = create(:workspace)
      abandoned = create(:sync_run, workspace:, status: :running, started_at: 1.hour.ago)
      finished = create(:sync_run, workspace:, status: :succeeded, started_at: 2.hours.ago, finished_at: 1.hour.ago)
      elsewhere = create(:sync_run, status: :running, started_at: 1.hour.ago)

      described_class.fail_abandoned(workspace)

      expect(abandoned.reload).to have_attributes(status: "failed", finished_at: be_present)
      expect(finished.reload).to be_succeeded
      expect(elsewhere.reload).to be_running
    end
  end
end
