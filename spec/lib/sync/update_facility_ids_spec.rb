require "rails_helper"

# Task 10 of planning/plans/phase-2-ingestion.md: Sync::UpdateFacilityIds is
# the fourth Sync::BasePhase subclass and the one deliberately adapted phase
# in the sync (spec D7 / planning/specs/2026-07-07-mclassrooms-design.md).
# It mirrors Sync::UpdateCampuses/UpdateBuildings/UpdateRooms's shape (real
# UmApi::Client stubbed via WebMock, Current.workspace set explicitly,
# changed_after_assign for accurate counters) but pins three things unique to
# this phase:
#
# 1. MATCH, NEVER CREATE — rooms already exist (Sync::UpdateRooms, Task 9).
#    A classroom-list row with no matching room by rmrecnbr is skipped and
#    counted/warned, never used to build a new Room.
# 2. CLEAR-NOT-DEACTIVATE (the adaptation) — the legacy app deactivated any
#    room absent from the Classroom List feed, which is safe only when the
#    DB holds classrooms exclusively. Now that Sync::UpdateRooms ingests
#    every room type (Brief §14.2), that same rule would wrongly wipe out
#    every office/lab nightly. Instead, a room that PREVIOUSLY had a
#    facility_code but has dropped out of the classroom list gets
#    `facility_code: nil` (facility_code_normalized clears too, via the
#    phase-1 before_save) — it drops out of Find-a-Room via the D8 classroom
#    scope (`where.not(facility_code: nil)`), the same user-visible effect
#    as the old deactivation, but self-healing and `in_feed`-untouched
#    (`in_feed` is owned solely by Sync::UpdateRooms). Dry-run reports the
#    would-clear set without writing.
# 3. Capacity bound recompute (D12) — `Setting.recompute_capacity_filter_max!`
#    runs at the very END of #perform, after the upsert + clear sweep, so it
#    only ever fires once the whole phase body has completed without
#    raising. An induced mid-phase failure must leave the setting untouched;
#    BasePhase's own rescue (never propagate) is what turns that raise into
#    a failed phase.
#
# classroom_list.json (Task 2 fixture): RmRecNbr 2005046 -> FacilityCd
# "MLB1200", Capacity 60; RmRecNbr 2005090 -> FacilityCd "AH0100",
# Capacity 0 (deliberately fails the D8 classroom listing rule elsewhere —
# not this phase's concern; this phase writes whatever seat count the feed
# reports, capacity-filtering is a display-scope decision).
#
# Endpoint path ("/bf/Buildings/v2/Classrooms"): mirrors Campuses's own
# flat sub-resource convention off "/bf/Buildings/v2" (see
# Sync::UpdateCampuses's header comment) — a best-effort guess pending
# phase 8's credentialed cutover, like every other phase's path constants.
RSpec.describe Sync::UpdateFacilityIds do
  around do |example|
    original = %w[UM_API_BASE_URL UM_API_TOKEN_URL UM_API_CLIENT_ID UM_API_CLIENT_SECRET].index_with { |key| ENV[key] }

    ENV["UM_API_BASE_URL"] = UmApiStubs::DEFAULT_BASE_URL
    ENV["UM_API_TOKEN_URL"] = UmApiStubs::DEFAULT_TOKEN_URL
    ENV["UM_API_CLIENT_ID"] = "test-client"
    ENV["UM_API_CLIENT_SECRET"] = "test-secret"

    example.run

    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  let(:workspace) { create(:workspace) }
  let(:run) { create(:sync_run, workspace: workspace) }
  # A no-op sleeper avoids a REAL 61s sleep in the 429-retry example below —
  # UmApi::Client.new's default RateLimiter uses Kernel.sleep, which every
  # other phase spec gets away with only because none of them ever trips a
  # 429. sleep_count still increments normally (real bookkeeping), so
  # `rate_limit_sleeps` assertions below have teeth.
  let(:client) { UmApi::Client.new(rate_limiter: UmApi::RateLimiter.new(sleeper: ->(_seconds) { })) }
  let!(:campus) { create(:campus, workspace: workspace, code: "100") }
  let!(:building) { create(:building, workspace: workspace, campus: campus) }

  before do
    Current.workspace = workspace
    stub_um_token(scope: "classrooms")
  end

  def phase = run.sync_phases.find_by!(key: "facility_ids")

  # See update_campuses_spec.rb's identical helper: an untouched counter is
  # ABSENT from the hash, not present-and-zero, so #fetch(..., 0) has teeth
  # either way.
  def counter(phase, key) = phase.counters.fetch(key.to_s, 0)

  def stub_classroom_list
    stub_um_get("/bf/Buildings/v2/Classrooms", fixture: "classroom_list.json", query: { "limit" => "1000" })
  end

  describe "matching classroom-list rows to existing rooms by rmrecnbr" do
    it "sets facility_code, instructional_seat_count, and campus on a matched room" do
      german = create(:room, workspace: workspace, building: building, rmrecnbr: "2005046",
        facility_code: nil, instructional_seat_count: nil, campus: nil)
      stub_classroom_list

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      german.reload
      expect(german.facility_code).to eq("MLB1200")
      expect(german.facility_code_normalized).to eq("mlb1200")
      expect(german.instructional_seat_count).to eq(60)
      expect(german.campus).to eq(campus)

      expect(phase).to be_succeeded
      expect(phase.counters).to include("updated" => 1, "api_calls" => 1, "rate_limit_sleeps" => 0)
      expect(counter(phase, :created)).to eq(0)
    end

    it "matches a second row against a second room independently" do
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005046", facility_code: nil, instructional_seat_count: nil)
      ah = create(:room, workspace: workspace, building: building, rmrecnbr: "2005090", facility_code: nil, instructional_seat_count: nil)
      stub_classroom_list

      described_class.call(run: run, client: client)

      expect(ah.reload.facility_code).to eq("AH0100")
      expect(ah.instructional_seat_count).to eq(0)
    end

    it "does not count a no-op update when the fetched row matches what's already stored" do
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005046",
        facility_code: "MLB1200", instructional_seat_count: 60, campus: campus)
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005090",
        facility_code: "AH0100", instructional_seat_count: 0, campus: campus)
      stub_classroom_list

      described_class.call(run: run, client: client)

      expect(counter(phase, :updated)).to eq(0)
    end

    it "skips a classroom-list row with no matching room, without creating one" do
      stub_classroom_list

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(Room.for_current_workspace.exists?(rmrecnbr: "2005046")).to be false
      expect(Room.for_current_workspace.exists?(rmrecnbr: "2005090")).to be false
      expect(Room.for_current_workspace.count).to eq(0)
      expect(counter(phase, :skipped)).to eq(2)
      expect(phase.warnings).to include(a_string_matching(/2005046/))
      expect(phase.warnings).to include(a_string_matching(/2005090/))
    end
  end

  describe "clear-not-deactivate (spec D7)" do
    it "clears facility_code on a room previously coded but no longer in the classroom list, leaving in_feed untouched" do
      stale = create(:room, workspace: workspace, building: building, rmrecnbr: "9999999",
        facility_code: "OLD9999", in_feed: true)
      stub_classroom_list

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      stale.reload
      expect(stale.facility_code).to be_nil
      expect(stale.facility_code_normalized).to be_nil
      expect(stale.in_feed).to be true
      expect(phase.counters).to include("cleared" => 1)
    end

    it "never touches a non-classroom room that never had a facility_code" do
      office = create(:room, workspace: workspace, building: building, rmrecnbr: "8888888",
        facility_code: nil, room_type: "Office", in_feed: true)
      stub_classroom_list

      described_class.call(run: run, client: client)

      expect(office.reload.facility_code).to be_nil
      expect(office.reload.in_feed).to be true
      expect(counter(phase, :cleared)).to eq(0)
    end

    it "does not clear a room whose rmrecnbr is still present in the feed" do
      german = create(:room, workspace: workspace, building: building, rmrecnbr: "2005046", facility_code: "MLB1200")
      stub_classroom_list

      described_class.call(run: run, client: client)

      expect(german.reload.facility_code).to eq("MLB1200")
      expect(counter(phase, :cleared)).to eq(0)
    end

    describe "dry run (Brief §6.1 API_UPDATE_DELETE_DRY_RUN)" do
      it "reports the would-clear list without writing, and does not touch in_feed" do
        dry_run = create(:sync_run, workspace: workspace, dry_run: true)
        stale = create(:room, workspace: workspace, building: building, rmrecnbr: "9999998",
          facility_code: "OLD8888", in_feed: true)
        stub_classroom_list

        result = described_class.call(run: dry_run, client: client)

        expect(result).to be_success
        stale.reload
        expect(stale.facility_code).to eq("OLD8888")
        expect(stale.in_feed).to be true

        dry_phase = dry_run.sync_phases.find_by!(key: "facility_ids")
        expect(dry_phase.counters).to include("cleared" => 1)
        expect(dry_phase.warnings).to include(a_string_matching(/9999998/))
      end
    end
  end

  describe "empty-feed guard" do
    it "does not clear any facility_code and warns when the classroom list feed returns zero rows" do
      untouched = create(:room, workspace: workspace, building: building, rmrecnbr: "7777777",
        facility_code: "KEEP7777", in_feed: true)
      stub_um_get("/bf/Buildings/v2/Classrooms", fixture: "classroom_list_empty.json", query: { "limit" => "1000" })

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(phase).to be_succeeded
      expect(untouched.reload.facility_code).to eq("KEEP7777")
      expect(counter(phase, :cleared)).to eq(0)
      expect(phase.warnings).to include(a_string_matching(/zero rows/i))
    end
  end

  describe "per-item backoff_429 retry (Brief §6.1 phase 4)" do
    it "retries after a transient 429 from the classroom list endpoint and still succeeds" do
      url = "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2/Classrooms"
      stub_request(:get, url)
        .with(query: { "limit" => "1000" })
        .to_return(
          { status: 429, body: "" },
          { status: 200, headers: UmApiStubs::JSON_RESPONSE_HEADERS, body: um_api_fixture("classroom_list.json") }
        )
      german = create(:room, workspace: workspace, building: building, rmrecnbr: "2005046", facility_code: nil)

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(german.reload.facility_code).to eq("MLB1200")
      expect(counter(phase, :rate_limit_sleeps)).to eq(1)
    end
  end

  describe "capacity_filter_max recompute (D12)" do
    it "recomputes Setting.capacity_filter_max from ingested seat counts after a successful run" do
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005046",
        room_type: "Classroom", facility_code: nil, instructional_seat_count: nil)
      stub_classroom_list

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(Setting.capacity_filter_max).to eq(75) # ceil(60 / 25.0) * 25
    end

    it "does not recompute capacity_filter_max when the phase fails mid-run" do
      Setting.capacity_filter_max = 50
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005046", facility_code: nil)
      stub_classroom_list
      allow_any_instance_of(Room).to receive(:update!).and_raise("boom mid-facility-sync")

      result = described_class.call(run: run, client: client)

      expect(result).not_to be_success
      expect(phase).to be_failed
      expect(Setting.capacity_filter_max).to eq(50)
    end
  end

  describe "idempotency" do
    it "reports 0 updated/cleared/skipped on a second run against the same feed" do
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005046", facility_code: nil, instructional_seat_count: nil)
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005090", facility_code: nil, instructional_seat_count: nil)
      stub_classroom_list

      described_class.call(run: run, client: client)
      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(counter(phase, :updated)).to eq(0)
      expect(counter(phase, :cleared)).to eq(0)
      expect(counter(phase, :skipped)).to eq(0)
    end
  end
end
