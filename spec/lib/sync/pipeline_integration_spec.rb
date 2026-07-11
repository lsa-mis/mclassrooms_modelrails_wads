require "rails_helper"

# Task 13 of planning/plans/phase-2-ingestion.md — the phase-2 gate. Every
# other spec/lib/sync/*_spec.rb file exercises exactly ONE phase in
# isolation (a real client + WebMock, but only that phase's own endpoints
# stubbed). This file is the first (and only) place `Sync::RunPipeline`
# drives all SIX real Sync::BasePhase subclasses back-to-back against the
# COMPLETE WebMock fixture set — no phase doubles anywhere. If a phase's
# endpoint path/query doesn't match what another phase (or this spec)
# expects, or two phases disagree about a room's shape, this is where that
# surfaces: as a WebMock::NetConnectNotAllowedError (a missing stub) or a
# wrong assertion, not a silent gap.
#
# `sleeper:` is a no-op lambda (spec D7: `PHASE_PAUSE_SECONDS` is 61 real
# seconds between each of the 6 core phases; a bare `Sync::RunPipeline.call`
# would sleep ~5*61s per run in this file alone). `client:` is left at its
# default (a real `UmApi::Client.new`, per Task 12) — every HTTP call it
# makes is intercepted by WebMock, never the network.
#
# Fixture-driven scope (spec/fixtures/um_api/): buildings_page1.json (MLB
# "1005046", AH "1005090", both campus "100") and buildings_page2.json (DEDC
# "1005200", campus "250") give one in-scope and one out-of-scope campus;
# only a `campus_allow: "100"` SyncScopeRule (set once, top-level `before`)
# is needed for DEDC to be filtered by Sync::UpdateBuildings — which matters
# for wiring, not just filtering: Sync::UpdateRooms walks
# `Building.for_current_workspace`, so DEDC never being persisted is also
# why this spec never needs a rooms-feed stub for it.
#
# Facility codes end up on exactly two rooms after Sync::UpdateFacilityIds
# matches classroom_list.json: MLB1200 (rmrecnbr 2005046, the German
# Classroom in MLB, seats 60) and AH0100 (rmrecnbr 2005090, the Math
# Classroom in AH, seats 0) — those are the only two facility codes
# Sync::UpdateCharacteristics/UpdateContacts ever request per-classroom
# endpoints for in the two "clean" examples below. AH0100 is stubbed with
# characteristics_empty.json (no characteristics_AH0100.json fixture exists;
# an empty response is a legitimate, distinct shape already exercised in
# isolation by update_characteristics_spec.rb) and contacts_AH0100.json
# (which does exist and is exercised for real here).
RSpec.describe "Sync::RunPipeline full pipeline integration (Task 13)",
  skip: "restored in sync-fix Task 5 once all phases migrate to the real gateway shapes" do
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
  # A no-op sleeper for Sync::RunPipeline's OWN 61s inter-phase pause (5 gaps
  # across the 6 core phases). Note this is a DIFFERENT sleeper from
  # UmApi::RateLimiter's (which defaults to Kernel.sleep) — this spec never
  # trips the rate limiter's own 400-calls/minute or 429-backoff sleeps (far
  # too few requests), so the default real client is safe to use unmodified.
  let(:no_op_sleeper) { ->(_seconds) { } }
  let(:fiscal_year) { UmApi.fiscal_year(Date.current) }

  before do
    Current.workspace = workspace
    # In scope for every example: only campus "100" (MLB/AH). DEDC
    # (campus "250", buildings_page2.json) is filtered out.
    create(:sync_scope_rule, workspace: workspace, rule_type: "campus_allow", value: "100")
  end

  def run_pipeline(**kwargs) = Sync::RunPipeline.call(sleeper: no_op_sleeper, **kwargs)

  def phase_for(run, key) = run.sync_phases.find_by!(key: key)

  # Mirrors every per-phase spec's identical helper: an untouched counter is
  # ABSENT from the hash, not present-and-zero, so #fetch(..., 0) has teeth
  # either way.
  def counter(phase, key) = phase.counters.fetch(key.to_s, 0)

  # ---- Stub helpers, one per endpoint family, composed by #stub_full_feed_set ----

  def stub_tokens
    stub_um_token(scope: "buildings")
    stub_um_token(scope: "department")
    stub_um_token(scope: "classrooms")
  end

  def stub_campuses_feed
    stub_um_get("/bf/Buildings/v2/Campuses", fixture: "campuses.json", query: { "limit" => "1000" })
  end

  def stub_buildings_feed
    stub_um_get("/bf/Buildings/v2", fixture: "buildings_page1.json",
      query: { "limit" => "1000", "fiscalYear" => fiscal_year.to_s },
      next_link: "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2?page=2")
    stub_um_get("/bf/Buildings/v2", fixture: "buildings_page2.json", query: { "page" => "2" })
  end

  def stub_rooms_feed
    stub_um_get("/bf/Buildings/v2/Departments", fixture: "departments.json", query: { "limit" => "1000" })
    stub_um_get("/bf/Buildings/v2/Departments/190100", fixture: "department_190100.json")
    stub_um_get("/bf/Buildings/v2/1005046/Rooms", fixture: "rooms_1005046.json", query: { "limit" => "1000" })
    stub_um_get("/bf/Buildings/v2/1005090/Rooms", fixture: "rooms_1005090.json", query: { "limit" => "1000" })
  end

  def stub_facility_ids_feed
    stub_um_get("/bf/Buildings/v2/Classrooms", fixture: "classroom_list.json", query: { "limit" => "1000" })
  end

  def stub_characteristics_feed
    stub_um_get("/bf/Buildings/v2/Classrooms/MLB1200/Characteristics", fixture: "characteristics_MLB1200.json")
    stub_um_get("/bf/Buildings/v2/Classrooms/AH0100/Characteristics", fixture: "characteristics_empty.json")
  end

  def stub_contacts_feed
    stub_um_get("/bf/Buildings/v2/Classrooms/MLB1200/Contacts", fixture: "contacts_MLB1200.json")
    stub_um_get("/bf/Buildings/v2/Classrooms/AH0100/Contacts", fixture: "contacts_AH0100.json")
  end

  # The full endpoint set every one of the six core phases hits on a run
  # where MLB/AH are the only in-scope buildings. A single `stub_request`
  # registration matches an UNLIMITED number of requests (WebMock's default),
  # so calling this ONCE per example is enough even when a test invokes
  # Sync::RunPipeline.call twice (each call builds its OWN UmApi::Client,
  # Task 12, so tokens and every listing endpoint are legitimately re-fetched
  # — same stubs, matched again).
  def stub_full_feed_set
    stub_tokens
    stub_campuses_feed
    stub_buildings_feed
    stub_rooms_feed
    stub_facility_ids_feed
    stub_characteristics_feed
    stub_contacts_feed
  end

  describe "a full successful run against the complete fixture set" do
    it "runs the 6 core phases to success with plausible counters" do
      stub_full_feed_set

      run = run_pipeline

      expect(run).to be_succeeded
      expect(run.finished_at).to be_present
      expect(run.sync_phases.count).to eq(6)
      expect(run.sync_phases.pluck(:key)).to match_array(Sync::RunPipeline::CORE_PHASES.map { |phase_class| phase_class::KEY })
      expect(run.sync_phases.pluck(:status).uniq).to eq([ "succeeded" ])

      campuses = phase_for(run, "campuses")
      expect(campuses.counters).to include("created" => 2, "api_calls" => 1)
      expect(counter(campuses, :deleted)).to eq(0)

      buildings = phase_for(run, "buildings")
      expect(buildings.counters).to include("created" => 2, "api_calls" => 2)
      expect(counter(buildings, :updated)).to eq(0)

      rooms = phase_for(run, "rooms")
      expect(rooms.counters).to include("created" => 4, "api_calls" => 4)
      expect(counter(rooms, :deactivated)).to eq(0)

      facility_ids = phase_for(run, "facility_ids")
      expect(facility_ids.counters).to include("updated" => 2, "api_calls" => 1)
      expect(counter(facility_ids, :skipped)).to eq(0)

      characteristics = phase_for(run, "characteristics")
      expect(characteristics.counters).to include("added" => 3, "api_calls" => 2)
      expect(counter(characteristics, :removed)).to eq(0)

      contacts = phase_for(run, "contacts")
      expect(contacts.counters).to include("updated" => 2, "api_calls" => 2)
    end

    it "populates every model with the fixture-derived data (campuses/buildings/floors/units/rooms/characteristics/contacts)" do
      stub_full_feed_set

      run_pipeline

      expect(Campus.for_current_workspace.pluck(:code)).to contain_exactly("100", "250")

      expect(Building.for_current_workspace.pluck(:bldrecnbr)).to contain_exactly("1005046", "1005090")
      expect(Building.for_current_workspace.exists?(bldrecnbr: "1005200")).to be false # DEDC, campus 250, out of scope

      # Floors are created from room labels: MLB gives "1"/"B"/"3", AH gives "0".
      expect(Floor.for_current_workspace.count).to eq(4)

      # Every room's department group collapses to the ONE COLLEGE_OF_LSA
      # unit (German 190000, Chem-lab 190100 via fallback, Math 180000 all
      # share the group code, Task 9's D10 keying rule).
      expect(Unit.for_current_workspace.count).to eq(1)
      unit = Unit.for_current_workspace.sole
      expect(unit.department_group).to eq("COLLEGE_OF_LSA")

      # ALL room types ingested (Task 9 / Brief §14.2), not just Classroom.
      expect(Room.for_current_workspace.pluck(:room_type))
        .to contain_exactly("Classroom", "Class Laboratory", "Office", "Classroom")

      german = Room.for_current_workspace.find_by!(rmrecnbr: "2005046")
      expect(german.facility_code).to eq("MLB1200")
      expect(german.facility_code_normalized).to eq("mlb1200")
      expect(german.instructional_seat_count).to eq(60)
      expect(german.unit).to eq(unit)
      expect(german.building).to eq(Building.for_current_workspace.find_by!(bldrecnbr: "1005046"))

      office = Room.for_current_workspace.find_by!(rmrecnbr: "2005048")
      expect(office.room_type).to eq("Office")
      expect(office.unit_id).to be_nil # blank department group -> admin-only, no unit (Brief §14.1)

      # Characteristics normalize their short_code through the shared
      # CodeNormalizer (downcase, strip non-alphanumeric): "Whtbrd>25" ->
      # "whtbrd25".
      expect(german.room_characteristics.pluck(:short_code)).to contain_exactly("instrcomp", "lecturecap", "whtbrd25")
      expect(german.room_characteristics.find_by!(code: "WHTBD25").short_code).to eq("whtbrd25")

      math = Room.for_current_workspace.find_by!(rmrecnbr: "2005090")
      expect(math.facility_code).to eq("AH0100")
      expect(math.room_contact.scheduling_name).to eq("Angell Hall Scheduling")
      expect(german.room_contact.scheduling_name).to eq("LSA Classroom Scheduling")
      expect(german.room_contact.support_phone).to be_nil # JSON null coerced, never ""
    end

    it "recomputes Setting.capacity_filter_max from the ingested seat counts (D12)" do
      stub_full_feed_set

      run_pipeline

      # ceil(60 / 25.0) * 25 = 75 (MLB1200's 60 seats; AH0100's 0 seats fails
      # Room.classroom's `instructional_seat_count: 2..` floor and never
      # contributes to the max).
      expect(Setting.capacity_filter_max).to eq(75)
    end
  end

  describe "stale room deactivation preserves hidden_at (D6), and a second run is idempotent" do
    it "deactivates a pre-existing out-of-feed room while keeping hidden_at, then creates nothing new on re-run" do
      # Pre-seed the MLB building itself (simulating "yesterday's data") so
      # Sync::UpdateBuildings UPDATES it in place instead of creating it, and
      # so the stale room below belongs to a building Sync::UpdateRooms
      # actually walks (any building not in the feed would make this
      # spec require a rooms-feed stub of its own).
      mlb_building = create(:building, workspace: workspace, bldrecnbr: "1005046", name: "Old MLB Name")
      stale_room = create(:room, :hidden, workspace: workspace, building: mlb_building,
        rmrecnbr: "9999999", facility_code: nil, in_feed: true)
      original_hidden_at = stale_room.hidden_at
      stub_full_feed_set

      run1 = run_pipeline

      expect(run1).to be_succeeded
      expect(stale_room.reload.in_feed).to be false
      expect(stale_room.hidden_at).to be_within(1.second).of(original_hidden_at)
      expect(phase_for(run1, "rooms").warnings).to be_empty # deactivation itself isn't warned; only the empty-feed guard warns

      run2 = run_pipeline

      expect(run2).to be_succeeded
      expect(run2.id).not_to eq(run1.id)
      expect(run2.sync_phases.count).to eq(6)
      expect(run2.sync_phases.pluck(:status).uniq).to eq([ "succeeded" ])

      # 0 created anywhere, and no unexpected reactivation/deactivation churn.
      Sync::RunPipeline::CORE_PHASES.each do |phase_class|
        expect(counter(phase_for(run2, phase_class::KEY), :created)).to eq(0)
      end
      expect(counter(phase_for(run2, "buildings"), :updated)).to eq(0)
      expect(counter(phase_for(run2, "rooms"), :updated)).to eq(0)
      expect(counter(phase_for(run2, "facility_ids"), :updated)).to eq(0)
      expect(counter(phase_for(run2, "facility_ids"), :cleared)).to eq(0)
      expect(counter(phase_for(run2, "characteristics"), :added)).to eq(0)
      expect(counter(phase_for(run2, "characteristics"), :removed)).to eq(0)
      expect(counter(phase_for(run2, "contacts"), :updated)).to eq(0)

      expect(stale_room.reload.in_feed).to be false # still deactivated, not reactivated
      expect(stale_room.hidden_at).to be_within(1.second).of(original_hidden_at)
      expect(Room.for_current_workspace.count).to eq(5) # 4 real feed rooms + the 1 permanently-stale room
      expect(Campus.for_current_workspace.count).to eq(2)
      expect(Building.for_current_workspace.count).to eq(2)
    end
  end

  describe "dry run writes no destructive changes anywhere in the pipeline" do
    it "completes successfully while hard-deletes, deactivations, and clears/removals are all previewed, not executed" do
      # One stale, unreferenced Campus — would normally be hard-deleted
      # (Task 7, the sync's ONE hard-delete).
      create(:campus, workspace: workspace, code: "999", description: "Retired Campus")

      # Pre-seed MLB (see the idempotency example above for why) plus three
      # rooms exercising every OTHER destructive sweep in the pipeline:
      mlb_building = create(:building, workspace: workspace, bldrecnbr: "1005046", name: "Old MLB Name")
      stale_room = create(:room, workspace: workspace, building: mlb_building,
        rmrecnbr: "9999999", facility_code: nil, in_feed: true) # rooms: would-deactivate
      stale_facility_room = create(:room, workspace: workspace, building: mlb_building,
        rmrecnbr: "8888888", facility_code: "OLD8888", in_feed: true) # facility_ids: would-clear
      german_room = create(:room, workspace: workspace, building: mlb_building,
        rmrecnbr: "2005046", facility_code: "MLB1200", in_feed: true) # the REAL feed row for this rmrecnbr
      departed_characteristic = create(:room_characteristic, workspace: workspace, room: german_room,
        code: "OLDCHAR", short_code: "oldchar") # characteristics: would-remove

      stub_full_feed_set
      # stale_facility_room's "OLD8888" facility_code is NOT cleared under
      # dry-run (that's the behavior under test), so it's still a
      # facility-coded room when Characteristics/Contacts iterate
      # `Room.where.not(facility_code: nil)` later in the same run.
      stub_um_get("/bf/Buildings/v2/Classrooms/OLD8888/Characteristics", fixture: "characteristics_empty.json")
      stub_um_get("/bf/Buildings/v2/Classrooms/OLD8888/Contacts", fixture: "contacts_MLB1200.json")

      run = Sync::RunPipeline.call(dry_run: true, sleeper: no_op_sleeper)

      expect(run).to be_succeeded
      expect(run).to be_dry_run
      expect(run.sync_phases.count).to eq(6)
      expect(run.sync_phases.pluck(:status).uniq).to eq([ "succeeded" ])

      # Nothing destructive actually happened...
      expect(Campus.for_current_workspace.exists?(code: "999")).to be true
      expect(stale_room.reload.in_feed).to be true
      expect(stale_facility_room.reload.facility_code).to eq("OLD8888")
      expect(stale_facility_room.reload.in_feed).to be true
      expect(RoomCharacteristic.exists?(departed_characteristic.id)).to be true

      # ...but every preview is still reported in counters/warnings.
      expect(counter(phase_for(run, "campuses"), :deleted)).to eq(1)

      rooms_phase = phase_for(run, "rooms")
      expect(counter(rooms_phase, :deactivated)).to eq(2) # stale_room + stale_facility_room
      expect(rooms_phase.warnings).to include(a_string_matching(/9999999/))

      facility_ids_phase = phase_for(run, "facility_ids")
      expect(counter(facility_ids_phase, :cleared)).to eq(1)
      expect(facility_ids_phase.warnings).to include(a_string_matching(/8888888/))

      characteristics_phase = phase_for(run, "characteristics")
      expect(counter(characteristics_phase, :removed)).to eq(1)
      expect(characteristics_phase.warnings).to include(a_string_matching(/OLDCHAR/))

      # Dry-run still upserts (routine, non-destructive, per BasePhase's
      # contract) — the German room's real characteristics from the feed ARE
      # created even though nothing already on file was removed.
      expect(RoomCharacteristic.where(room: german_room, code: "INSTRCOMP")).to exist
    end
  end
end
