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

    it "also fails the abandoned run's step that was mid-flight, so it does not keep showing Running" do
      workspace = create(:workspace)
      abandoned = create(:sync_run, workspace:, status: :running, started_at: 1.hour.ago)
      done = create(:sync_phase, sync_run: abandoned, key: "campuses", status: :succeeded)
      mid_flight = create(:sync_phase, sync_run: abandoned, key: "buildings", status: :running)
      other_live = create(:sync_phase, sync_run: create(:sync_run, status: :running), key: "rooms", status: :running)

      described_class.fail_abandoned(workspace)

      expect(mid_flight.reload).to have_attributes(status: "failed", finished_at: be_present)
      expect(done.reload).to be_succeeded
      expect(other_live.reload).to be_running
    end
  end

  describe "#retryable?" do
    let(:workspace) { create(:workspace) }

    it "is true only for the workspace's most recent run, and only when it failed" do
      older = create(:sync_run, workspace:, status: :failed, started_at: 2.days.ago, finished_at: 2.days.ago)
      newest = create(:sync_run, workspace:, status: :failed, started_at: 1.day.ago, finished_at: 1.day.ago)
      create(:sync_run, status: :failed, started_at: 1.hour.ago)

      expect(newest).to be_retryable
      expect(older).not_to be_retryable
    end

    it "is false for the most recent run when it did not fail" do
      run = create(:sync_run, workspace:, status: :succeeded, started_at: 1.day.ago, finished_at: 1.day.ago)

      expect(run).not_to be_retryable
    end
  end

  describe "progress" do
    let(:workspace) { create(:workspace) }
    let(:run) { create(:sync_run, workspace:, status: :running, started_at: 5.minutes.ago) }

    it "counts finished core steps and names the one running" do
      create(:sync_phase, sync_run: run, key: "campuses", status: :succeeded)
      create(:sync_phase, sync_run: run, key: "buildings", status: :succeeded)
      rooms = create(:sync_phase, sync_run: run, key: "rooms", status: :running)

      expect([ run.steps_done, run.steps_total, run.current_phase ]).to eq([ 2, 6, rooms ])
    end

    it "counts the running step's share of its items toward the bar" do
      %w[campuses buildings rooms].each { create(:sync_phase, sync_run: run, key: it, status: :succeeded) }
      facility_ids = create(:sync_phase, sync_run: run, key: "facility_ids", status: :running)

      expect(run.progress_percent).to eq(50)
      facility_ids.update!(items_done: 612, items_total: 1067)
      expect(run.reload.progress_percent).to eq(59)
    end

    it "lists the changes each step made, in step order, leaving out calls and skips" do
      create(:sync_phase, sync_run: run, key: "contacts", counters: { "updated" => 1, "api_calls" => 461 })
      create(:sync_phase, sync_run: run, key: "rooms", counters: { "created" => 1, "updated" => 3, "deactivated" => 0, "skipped" => 2 })

      expect(run.changes_made).to eq([ [ "rooms_created", 1 ], [ "rooms_updated", 3 ], [ "contacts_updated", 1 ] ])
      expect(run.change_count).to eq(5)
    end

    it "takes the typical duration from the newest finished real sync" do
      create(:sync_run, workspace:, status: :succeeded, started_at: 2.days.ago, finished_at: 2.days.ago + 30.minutes)
      create(:sync_run, workspace:, status: :succeeded, started_at: 1.day.ago, finished_at: 1.day.ago + 14.minutes)
      create(:sync_run, workspace:, status: :succeeded, dry_run: true, started_at: 1.hour.ago, finished_at: 1.hour.ago + 1.minute)
      create(:sync_run, workspace:, status: :failed, started_at: 2.hours.ago, finished_at: 2.hours.ago + 2.minutes)

      expect(described_class.typical_duration_for(workspace)).to be_within(1).of(14.minutes)
    end

    it "broadcasts a refresh to the workspace sync stream when a run or step changes" do
      stream = [ workspace, :sync_runs ].map { |s| s.try(:to_gid_param) || s.to_param }.join(":")
      run

      expect { run.update!(status: :succeeded, finished_at: Time.current) }.to have_broadcasted_to(stream)
      expect { create(:sync_phase, sync_run: run, key: "rooms", status: :running) }.to have_broadcasted_to(stream)
    end
  end
end
