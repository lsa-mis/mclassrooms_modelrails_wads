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
#    A discovered rmrecnbr with no matching room is skipped and
#    counted/warned, never used to build a new Room.
# 2. CLEAR-NOT-DEACTIVATE (the adaptation) — the legacy app deactivated any
#    room absent from the Classroom List feed, which is safe only when the
#    DB holds classrooms exclusively. Now that Sync::UpdateRooms ingests
#    every room type (Brief §14.2), that same rule would wrongly wipe out
#    every office/lab nightly. Instead, a room that PREVIOUSLY had a
#    facility_code but is not rediscovered this run gets `facility_code:
#    nil` (facility_code_normalized clears too, via the phase-1 before_save)
#    — it drops out of Find-a-Room via the D8 classroom scope
#    (`where.not(facility_code: nil)`), the same user-visible effect as the
#    old deactivation, but self-healing and `in_feed`-untouched (`in_feed`
#    is owned solely by Sync::UpdateRooms). Dry-run reports the would-clear
#    set without writing.
# 3. Capacity bound recompute (D12) — `Setting.recompute_capacity_filter_max!`
#    runs at the very END of #perform, after the upsert + clear sweep, so it
#    only ever fires once the whole phase body has completed without
#    raising. An induced mid-phase failure must leave the setting untouched;
#    BasePhase's own rescue (never propagate) is what turns that raise into
#    a failed phase.
#
# THE CROSSWALK (sync-fix Task 4 — the structural rewrite this file pins):
# the real facility list (`GET /aa/ClassroomList/v2/Classrooms`) carries
# only FacilityID/BuildingID — no RmRecNbr and no seat/Capacity field at
# all. The RmRecNbr<->FacilityID crosswalk lives ONLY in each facility's own
# `/Characteristics` sub-resource, so discovery is two HTTP round trips: one
# paged fetch of the flat facility list (`classroom_list.json`, grouped
# client-side by BuildingID), then one `get_json` per in-scope building's
# facility IDs against `/Classrooms/{FacilityID}/Characteristics`
# (`characteristics_MLB1200.json` et al) to read the RmRecNbr(s) it covers.
# `building` below is seeded with `bldrecnbr: "1005046"` — the exact
# BuildingID `classroom_list.json`'s single facility (MLB1200) maps to — so
# every example exercises the SAME building/facility resolution
# `Sync::UpdateRooms`'s own per-building walk would have produced.
# `instructional_seat_count` is NOT touched by this phase at all anymore
# (sync-fix Task 4): the real facility list has no seat field, so seats
# come exclusively from Sync::UpdateRooms's RoomInfo.RoomStationCount
# (see update_rooms_spec.rb) — a room's seed value below stands in for
# whatever that phase already persisted.
#
# Endpoint path ("/aa/ClassroomList/v2/Classrooms"): confirmed against live
# credentialed access (sync-fix Task 4).
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
  let!(:building) { create(:building, workspace: workspace, campus: campus, bldrecnbr: "1005046") }

  before do
    Current.workspace = workspace
    stub_um_token(scope: "classrooms")
  end

  def phase = run.sync_phases.find_by!(key: "facility_ids")

  # See update_campuses_spec.rb's identical helper: an untouched counter is
  # ABSENT from the hash, not present-and-zero, so #fetch(..., 0) has teeth
  # either way.
  def counter(phase, key) = phase.counters.fetch(key.to_s, 0)

  def stub_facility_list(fixture: "classroom_list.json")
    stub_um_get("/aa/ClassroomList/v2/Classrooms", fixture: fixture, query: { "$start_index" => "0", "$count" => "1000" })
  end

  def stub_facility_characteristics(facility_id: "MLB1200", fixture: "characteristics_MLB1200.json")
    stub_um_get("/aa/ClassroomList/v2/Classrooms/#{facility_id}/Characteristics", fixture: fixture)
  end

  # The default single-facility scenario: classroom_list.json maps ONE
  # facility (MLB1200, RmRecNbr 2005046 per characteristics_MLB1200.json) to
  # `building`.
  def stub_crosswalk
    stub_facility_list
    stub_facility_characteristics
  end

  describe "matching discovered rmrecnbrs to existing rooms" do
    it "sets facility_code and campus on a matched room" do
      german = create(:room, workspace: workspace, building: building, rmrecnbr: "2005046",
        facility_code: nil, campus: nil)
      stub_crosswalk

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      german.reload
      expect(german.facility_code).to eq("MLB1200")
      expect(german.facility_code_normalized).to eq("mlb1200")
      expect(german.campus).to eq(campus)

      expect(phase).to be_succeeded
      # api_calls: 1 (facility list) + 1 (MLB1200's Characteristics) = 2.
      expect(phase.counters).to include("updated" => 1, "api_calls" => 2, "rate_limit_sleeps" => 0)
      expect(counter(phase, :created)).to eq(0)
      expect(counter(phase, :skipped)).to eq(0)
    end

    it "does not set instructional_seat_count — that source moved to Sync::UpdateRooms (sync-fix Task 4)" do
      german = create(:room, workspace: workspace, building: building, rmrecnbr: "2005046",
        facility_code: nil, instructional_seat_count: 60)
      stub_crosswalk

      described_class.call(run: run, client: client)

      expect(german.reload.instructional_seat_count).to eq(60) # untouched, not derived from this feed
    end

    it "matches a second facility against a second room independently" do
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005046", facility_code: nil)
      ah = create(:room, workspace: workspace, building: building, rmrecnbr: "2005090", facility_code: nil)
      stub_facility_list(fixture: "classroom_list_two_facilities.json")
      stub_facility_characteristics(facility_id: "MLB1200", fixture: "characteristics_MLB1200.json")
      stub_facility_characteristics(facility_id: "AH0100", fixture: "characteristics_AH0100.json")

      described_class.call(run: run, client: client)

      expect(ah.reload.facility_code).to eq("AH0100")
    end

    it "does not count a no-op update when the discovered facility_code matches what's already stored" do
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005046",
        facility_code: "MLB1200", campus: campus)
      stub_crosswalk

      described_class.call(run: run, client: client)

      expect(counter(phase, :updated)).to eq(0)
    end

    it "skips a discovered rmrecnbr with no matching room, without creating one" do
      stub_crosswalk

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(Room.for_current_workspace.exists?(rmrecnbr: "2005046")).to be false
      expect(Room.for_current_workspace.count).to eq(0)
      expect(counter(phase, :skipped)).to eq(1)
      expect(phase.warnings).to include(a_string_matching(/2005046/))
    end

    # sync-fix Task 4 / sync-fix-plan.md §6 Risks: "a real facility can have
    # zero characteristics and therefore be undiscoverable" — an accepted
    # data gap in the proven recipe, not a bug. No crosswalk entry is
    # produced, and nothing is warned about beyond the ordinary
    # skip-on-no-match path (which never fires here, since there is nothing
    # to iterate).
    it "treats a facility whose Characteristics response is empty as undiscoverable, without raising" do
      stub_facility_list
      stub_facility_characteristics(fixture: "characteristics_empty.json")

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(phase).to be_succeeded
      expect(counter(phase, :skipped)).to eq(0)
      expect(counter(phase, :updated)).to eq(0)
    end
  end

  describe "clear-not-deactivate (spec D7)" do
    it "clears facility_code on a room previously coded but not rediscovered this run, leaving in_feed untouched" do
      stale = create(:room, workspace: workspace, building: building, rmrecnbr: "9999999",
        facility_code: "OLD9999", in_feed: true)
      stub_crosswalk

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
      stub_crosswalk

      described_class.call(run: run, client: client)

      expect(office.reload.facility_code).to be_nil
      expect(office.reload.in_feed).to be true
      expect(counter(phase, :cleared)).to eq(0)
    end

    it "does not clear a room whose rmrecnbr was rediscovered this run" do
      german = create(:room, workspace: workspace, building: building, rmrecnbr: "2005046", facility_code: "MLB1200")
      stub_crosswalk

      described_class.call(run: run, client: client)

      expect(german.reload.facility_code).to eq("MLB1200")
      expect(counter(phase, :cleared)).to eq(0)
    end

    describe "dry run (Brief §6.1 API_UPDATE_DELETE_DRY_RUN)" do
      it "reports the would-clear list without writing, and does not touch in_feed" do
        dry_run = create(:sync_run, workspace: workspace, dry_run: true)
        stale = create(:room, workspace: workspace, building: building, rmrecnbr: "9999998",
          facility_code: "OLD8888", in_feed: true)
        stub_crosswalk

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
    it "does not clear any facility_code and warns when the facility list feed returns zero rows" do
      untouched = create(:room, workspace: workspace, building: building, rmrecnbr: "7777777",
        facility_code: "KEEP7777", in_feed: true)
      stub_facility_list(fixture: "classroom_list_empty.json")

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(phase).to be_succeeded
      expect(untouched.reload.facility_code).to eq("KEEP7777")
      expect(counter(phase, :cleared)).to eq(0)
      expect(phase.warnings).to include(a_string_matching(/zero rows/i))
    end
  end

  # sync-fix Task 4: the old whole-walk retry (one backoff_429 wrapping the
  # ENTIRE classroom-list each_page walk) no longer applies — the facility
  # LIST fetch and each per-facility Characteristics fetch are now
  # INDEPENDENT network calls, each with its own backoff_429 (matching
  # Sync::UpdateCharacteristics/UpdateContacts's per-item retry shape). A
  # 429 on one retries only that one call.
  describe "backoff_429 retry (Brief §6.1 phase 4)" do
    it "retries after a transient 429 from the facility list endpoint and still succeeds" do
      german = create(:room, workspace: workspace, building: building, rmrecnbr: "2005046", facility_code: nil)
      url = "#{UmApiStubs::DEFAULT_BASE_URL}/aa/ClassroomList/v2/Classrooms"
      stub_request(:get, url)
        .with(query: { "$start_index" => "0", "$count" => "1000" })
        .to_return(
          { status: 429, body: "" },
          { status: 200, headers: UmApiStubs::JSON_RESPONSE_HEADERS, body: um_api_fixture("classroom_list.json") }
        )
      stub_facility_characteristics

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(german.reload.facility_code).to eq("MLB1200")
      expect(counter(phase, :rate_limit_sleeps)).to eq(1)
    end

    it "retries after a transient 429 from a single facility's Characteristics endpoint, without re-fetching the facility list" do
      german = create(:room, workspace: workspace, building: building, rmrecnbr: "2005046", facility_code: nil)
      list_stub = stub_facility_list
      url = "#{UmApiStubs::DEFAULT_BASE_URL}/aa/ClassroomList/v2/Classrooms/MLB1200/Characteristics"
      stub_request(:get, url).to_return(
        { status: 429, body: "" },
        { status: 200, headers: UmApiStubs::JSON_RESPONSE_HEADERS, body: um_api_fixture("characteristics_MLB1200.json") }
      )

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(german.reload.facility_code).to eq("MLB1200")
      expect(counter(phase, :rate_limit_sleeps)).to eq(1)
      expect(list_stub).to have_been_requested.once
    end
  end

  describe "capacity_filter_max recompute (D12)" do
    it "recomputes Setting.capacity_filter_max from seat counts Sync::UpdateRooms already persisted" do
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005046",
        room_type: "Classroom", facility_code: nil, instructional_seat_count: 60)
      stub_crosswalk

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(Setting.capacity_filter_max).to eq(75) # ceil(60 / 25.0) * 25
    end

    it "does not recompute capacity_filter_max when the phase fails mid-run" do
      Setting.capacity_filter_max = 50
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005046", facility_code: nil)
      stub_crosswalk
      allow_any_instance_of(Room).to receive(:update!).and_raise("boom mid-facility-sync")

      result = described_class.call(run: run, client: client)

      expect(result).not_to be_success
      expect(phase).to be_failed
      expect(Setting.capacity_filter_max).to eq(50)
    end
  end

  describe "idempotency" do
    it "reports 0 updated/cleared/skipped on a second run against the same feed" do
      create(:room, workspace: workspace, building: building, rmrecnbr: "2005046", facility_code: nil)
      stub_crosswalk

      described_class.call(run: run, client: client)
      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(counter(phase, :updated)).to eq(0)
      expect(counter(phase, :cleared)).to eq(0)
      expect(counter(phase, :skipped)).to eq(0)
    end
  end
end
