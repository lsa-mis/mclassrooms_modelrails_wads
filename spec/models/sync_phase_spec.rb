require "rails_helper"

RSpec.describe SyncPhase, type: :model do
  let(:record) { create(:sync_phase) }

  it_behaves_like "a tenanted directory record"

  describe "associations" do
    it "requires a sync_run" do
      phase = build(:sync_phase, sync_run: nil, workspace: create(:workspace))
      expect(phase).not_to be_valid
    end
  end

  describe "status enum" do
    it "defaults to pending" do
      run = create(:sync_run)
      phase = SyncPhase.create!(sync_run: run, workspace: run.workspace, key: "campuses")
      expect(phase.status).to eq("pending")
      expect(phase.pending?).to be true
    end

    it "supports running/succeeded/failed/skipped" do
      %w[running succeeded failed skipped].each do |status|
        phase = build(:sync_phase, status: status)
        expect(phase.public_send("#{status}?")).to be true
      end
    end

    it "raises ArgumentError for an unknown status" do
      phase = build(:sync_phase)
      expect { phase.status = "bogus" }.to raise_error(ArgumentError)
    end
  end

  describe "key" do
    it "is not implemented as a Rails enum (plain string column)" do
      expect(SyncPhase.defined_enums).not_to have_key("key")
    end

    it "is invalid when blank" do
      phase = build(:sync_phase, key: nil)
      expect(phase).not_to be_valid
    end

    it "is invalid with a key outside SyncPhase::KEYS" do
      phase = build(:sync_phase, key: "not_a_real_phase")
      expect(phase).not_to be_valid
      expect(phase.errors[:key]).not_to be_empty
    end

    it "accepts every documented phase key" do
      SyncPhase::KEYS.each do |key|
        expect(build(:sync_phase, key: key)).to be_valid
      end
    end

    it "is invalid with a duplicate (sync_run, key) pair" do
      run = create(:sync_run)
      create(:sync_phase, sync_run: run, workspace: run.workspace, key: "campuses")
      duplicate = build(:sync_phase, sync_run: run, workspace: run.workspace, key: "campuses")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key]).not_to be_empty
    end

    it "allows the same key on a different sync_run" do
      create(:sync_phase, key: "campuses")
      other = build(:sync_phase, key: "campuses")

      expect(other).to be_valid
    end
  end

  describe "JSON column defaults" do
    it "defaults counters/warnings/error_messages and round-trips as Hash/Array" do
      run = create(:sync_run)
      phase = SyncPhase.create!(sync_run: run, workspace: run.workspace, key: "campuses")
      phase.reload

      expect(phase.counters).to eq({})
      expect(phase.counters).to be_a(Hash)
      expect(phase.warnings).to eq([])
      expect(phase.warnings).to be_a(Array)
      expect(phase.error_messages).to eq([])
      expect(phase.error_messages).to be_a(Array)
    end

    it "persists assigned values" do
      phase = create(:sync_phase, counters: { "created" => 3 }, warnings: [ "slow page" ], error_messages: [ "boom" ])
      phase.reload

      expect(phase.counters).to eq({ "created" => 3 })
      expect(phase.warnings).to eq([ "slow page" ])
      expect(phase.error_messages).to eq([ "boom" ])
    end
  end

  describe "error_messages column" do
    it "is named error_messages, not errors (ActiveModel::Errors collision)" do
      expect(SyncPhase.column_names).to include("error_messages")
      expect(SyncPhase.column_names).not_to include("errors")
    end

    it "does not raise when instantiated (no DangerousAttributeError)" do
      expect { SyncPhase.new }.not_to raise_error
    end
  end

  describe "#duration_seconds" do
    it "returns nil when not started" do
      phase = build(:sync_phase, started_at: nil, finished_at: Time.current)
      expect(phase.duration_seconds).to be_nil
    end

    it "returns nil when not finished" do
      phase = build(:sync_phase, started_at: Time.current, finished_at: nil)
      expect(phase.duration_seconds).to be_nil
    end

    it "returns the elapsed seconds between started_at and finished_at" do
      started = Time.zone.parse("2026-01-01 00:00:00")
      finished = started + 90.seconds
      phase = build(:sync_phase, started_at: started, finished_at: finished)

      expect(phase.duration_seconds).to eq(90)
    end
  end

  describe "schema" do
    it "has a unique composite index on [sync_run_id, key]" do
      indexes = ActiveRecord::Base.connection.indexes("sync_phases")
      index = indexes.find { |i| i.columns == [ "sync_run_id", "key" ] }
      expect(index).to be_present, "Expected unique composite index on (sync_run_id, key)"
      expect(index.unique).to be true
    end
  end
end
