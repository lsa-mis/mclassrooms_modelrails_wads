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

  describe "operator actions" do
    include ActiveJob::TestHelper

    let(:workspace) { create(:workspace) }
    let(:operator) { create(:user) }

    describe ".request!" do
      it "queues a new run, audits it, and enqueues the pipeline for that run" do
        outcome = nil
        expect { outcome = described_class.request!(workspace:, by: operator) }
          .to change { described_class.where(workspace:).count }.by(1)

        run = described_class.where(workspace:).sole
        expect(outcome).to eq(:requested)
        expect(run).to be_queued
        expect(SyncRunJob).to have_been_enqueued.with(run)
        log = ActivityLog.find_by!(action: "sync_run.requested", trackable: run)
        expect([ log.actor, log.workspace, log.visibility ]).to eq([ operator, workspace, "admin" ])
      end

      it "refuses while a run is in progress, so a double click cannot start two" do
        described_class.request!(workspace:, by: operator)

        expect(described_class.request!(workspace:, by: operator)).to eq(:already_running)
        expect(described_class.where(workspace:).count).to eq(1)
      end

      it "is not blocked by a run that stalled hours ago" do
        create(:sync_run, workspace:, status: :running, started_at: 7.hours.ago)

        expect(described_class.request!(workspace:, by: operator)).to eq(:requested)
      end

      it "is not blocked by another workspace's run" do
        create(:sync_run, status: :running, started_at: 1.minute.ago)

        expect(described_class.request!(workspace:, by: operator)).to eq(:requested)
      end
    end

    describe "#resume!" do
      let(:run) { create(:sync_run, workspace:, status: :failed, started_at: 1.hour.ago, finished_at: 50.minutes.ago) }

      it "marks a failed run running at once, audits it, and enqueues the pipeline for it" do
        expect(run.resume!(by: operator)).to eq(:resumed)

        expect(run.reload).to be_running
        expect(run.finished_at).to be_nil
        expect(SyncRunJob).to have_been_enqueued.with(run)
        expect(ActivityLog.find_by!(action: "sync_run.resumed", trackable: run).actor).to eq(operator)
      end

      it "retries a stalled run" do
        stalled = create(:sync_run, workspace:, status: :running, started_at: 7.hours.ago)

        expect(stalled.resume!(by: operator)).to eq(:resumed)
      end

      it "refuses a succeeded run or one still in progress" do
        succeeded = create(:sync_run, workspace:, status: :succeeded, started_at: 2.hours.ago)
        running = create(:sync_run, workspace:, status: :running, started_at: 1.minute.ago)

        expect(succeeded.resume!(by: operator)).to eq(:not_resumable)
        expect(running.resume!(by: operator)).to eq(:not_resumable)
        expect(SyncRunJob).not_to have_been_enqueued
      end

      it "refuses while another run is in progress" do
        create(:sync_run, workspace:, status: :running, started_at: 1.minute.ago)

        expect(run.resume!(by: operator)).to eq(:already_running)
        expect(run.reload).to be_failed
      end

      it "gives a retried run a fresh start time, so an old failure is not stalled the moment it resumes" do
        old = create(:sync_run, workspace:, status: :failed, started_at: 10.hours.ago, finished_at: 9.hours.ago)

        old.resume!(by: operator)

        expect(old.reload.started_at).to be_within(5.seconds).of(Time.current)
        expect(old.display_status).to eq(:queued).or eq(:running)
        expect(described_class.in_progress_for?(workspace)).to be(true)
      end

      it "lets only one of two simultaneous retries claim the run" do
        first = described_class.find(run.id)
        second = described_class.find(run.id)

        expect(first.resume!(by: operator)).to eq(:resumed)
        expect(second.resume!(by: operator)).to eq(:not_resumable)
        expect(SyncRunJob).to have_been_enqueued.exactly(:once)
      end
    end

    describe "one running sync per workspace" do
      it "is enforced by the database, not only by the in-progress check" do
        create(:sync_run, workspace:, status: :running, started_at: 1.minute.ago)

        expect { create(:sync_run, workspace:, status: :running) }.to raise_error(ActiveRecord::RecordNotUnique)
        expect { create(:sync_run, status: :running) }.not_to raise_error
      end

      it "turns Run now away when the reservation loses a race the in-progress check missed" do
        allow(described_class).to receive(:in_progress_for?).and_return(false)
        create(:sync_run, workspace:, status: :running, started_at: 1.minute.ago)

        expect(described_class.request!(workspace:, by: operator)).to eq(:already_running)
        expect(ActivityLog.where(action: "sync_run.requested")).to be_empty
        expect(SyncRunJob).not_to have_been_enqueued
      end

      it "fails a stalled run before reserving, so it never blocks the next one" do
        stalled = create(:sync_run, workspace:, status: :running, started_at: 7.hours.ago)

        expect(described_class.request!(workspace:, by: operator)).to eq(:requested)
        expect(stalled.reload).to be_failed
      end
    end
  end

  describe "display state" do
    it "reads a run with no start time as queued and one running past the stall window as stalled" do
      expect(build(:sync_run, status: :running, started_at: nil, created_at: 1.minute.ago).display_status).to eq(:queued)
      expect(build(:sync_run, status: :running, started_at: 7.hours.ago).display_status).to eq(:stalled)
      expect(build(:sync_run, status: :running, started_at: 1.minute.ago).display_status).to eq(:running)
      expect(build(:sync_run, status: :failed).display_status).to eq(:failed)
    end

    it "lists its phases in pipeline order" do
      run = create(:sync_run)
      %w[rooms campuses buildings].each { |key| create(:sync_phase, sync_run: run, key:) }

      expect(run.phases_in_order.map(&:key)).to eq(%w[campuses buildings rooms])
    end
  end

  describe ".history_for and .inventory_for" do
    let(:workspace) { create(:workspace) }

    it "returns the workspace's newest fourteen runs, newest first" do
      runs = 16.times.map { |i| create(:sync_run, workspace:, status: :succeeded, started_at: i.hours.ago) }
      create(:sync_run, started_at: 1.minute.ago)

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

  describe ".latest" do
    it "returns the most recently started run" do
      workspace = create(:workspace)
      create(:sync_run, workspace: workspace, status: :succeeded, started_at: 2.days.ago)
      newer = create(:sync_run, workspace: workspace, started_at: 1.hour.ago)

      expect(SyncRun.latest).to eq(newer)
    end

    it "falls back to created_at when started_at is nil" do
      workspace = create(:workspace)
      create(:sync_run, workspace: workspace, status: :failed, started_at: nil)
      second_run = create(:sync_run, workspace: workspace, status: :failed, started_at: nil)

      expect(SyncRun.latest).to eq(second_run)
    end

    it "returns nil when there are no runs" do
      expect(SyncRun.latest).to be_nil
    end
  end
end
