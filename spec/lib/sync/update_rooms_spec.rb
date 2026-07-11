require "rails_helper"

# Task 9 of planning/plans/phase-2-ingestion.md: Sync::UpdateRooms is the
# largest and most intricate of the six Sync::BasePhase subclasses. It
# mirrors Sync::UpdateCampuses/UpdateBuildings's shape (real UmApi::Client
# stubbed via WebMock, `Current.workspace` set explicitly, `changed_after_
# assign` for accurate created/updated counters) but pins several structural
# differences unique to rooms:
#
# 1. ALL ROOM TYPES (Brief §14.2) — rooms_1005046.json deliberately mixes a
#    Classroom, a Class Laboratory, and an Office (blank department name) so
#    a `RoomTypeDescription == "Classroom"` filter (um_import's DEV-only
#    shortcut — sync-fix-decisions.md Risk 3 — NOT this phase's product
#    policy) would be caught immediately by the first describe block below.
# 2. Per-building walk — there is no flat rooms listing endpoint; this phase
#    walks `Building.for_current_workspace` (buildings must already exist —
#    seeded directly via the :building factory here, not through
#    Sync::UpdateBuildings) and fetches one paginated feed per building via
#    `GET /bf/Buildings/v2/RoomInfo/{bldrecnbr}`.
# 3. Department join by NAME, not id (sync-fix Task 3 — the structural
#    change of this rewrite) — RoomInfo carries no department id at all,
#    only a free-text `DepartmentName`. `departments.json` (the bulk
#    `GET /bf/Department/v2/DeptData` preload) omits "LSA - Chemistry" (the
#    Class Laboratory's department name) on purpose, so every example that
#    stubs the fallback endpoint is exercising a REAL miss resolved via the
#    `?DeptDescription=` query-param GET, not a no-op.
# 4. Deactivation is a single all-or-nothing TRANSACTION (Brief §6.1 phase
#    3), unlike Campus's per-record-rescued hard-delete (Task 7) or
#    Building's warn-only absence (Task 8) — the "rolls back" example below
#    induces a real failure mid-sweep and asserts the DB shows zero partial
#    deactivations, not just that the phase reports failure.
# 5. Floor-label normalization (new in this rewrite) — the Office room's
#    `FloorNumber` is deliberately `"03"` (not already-normalized `"3"`) so
#    the `normalize_floor_label` port from `UmImport` gets real teeth: the
#    persisted `Floor#label` must come back `"3"`, proving the leading zero
#    was actually stripped and not just passed through.
#
# Endpoint paths (`GET /bf/Buildings/v2/RoomInfo/{bldrecnbr}`,
# `GET /bf/Department/v2/DeptData` bulk + `?DeptDescription=` fallback) are
# confirmed against live credentialed access (sync-fix Task 3; see the
# proven reference `lib/tasks/um_import.rake`) — hardcoded here rather than
# referencing Sync::UpdateRooms's own constants, so this spec independently
# pins the external contract instead of trivially restating the
# implementation. The `?DeptDescription=` single-department fallback shape
# itself is flagged live-smoke-only (sync-fix-plan.md §5 Risks): `um_import`
# never needed to exercise it against real credentials (its bulk index
# matched every department it encountered), so this spec's fallback fixture
# is a best-effort reconstruction of the same `{"DepartmentList":
# {"DeptData": [...]}}` envelope the bulk endpoint returns, with 0 or 1 rows.
RSpec.describe Sync::UpdateRooms do
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
  let(:client) { UmApi::Client.new }
  let!(:building_mlb) { create(:building, workspace: workspace, bldrecnbr: "1005046", name: "Modern Languages Building") }
  let!(:building_ah) { create(:building, workspace: workspace, bldrecnbr: "1005090", name: "Angell Hall") }

  before do
    Current.workspace = workspace
    stub_um_token(scope: "buildings")
    stub_um_token(scope: "department")
  end

  def phase = run.sync_phases.find_by!(key: "rooms")

  # See update_campuses_spec.rb's identical helper: an untouched counter is
  # ABSENT from the hash, not present-and-zero, so #fetch(..., 0) has teeth
  # either way.
  def counter(phase, key) = phase.counters.fetch(key.to_s, 0)

  def stub_departments_feed
    stub_um_get("/bf/Department/v2/DeptData", fixture: "departments.json",
      query: { "$start_index" => "0", "$count" => "1000" })
  end

  def stub_department_fallback
    stub_um_get("/bf/Department/v2/DeptData", fixture: "department_190100.json",
      query: { "DeptDescription" => "LSA - Chemistry" })
  end

  def stub_rooms_feed
    stub_um_get("/bf/Buildings/v2/RoomInfo/1005046", fixture: "rooms_1005046.json",
      query: { "$start_index" => "0", "$count" => "1000" })
    stub_um_get("/bf/Buildings/v2/RoomInfo/1005090", fixture: "rooms_1005090.json",
      query: { "$start_index" => "0", "$count" => "1000" })
  end

  describe "all room types (Brief §14.2)" do
    it "ingests every room type across every building, including Office and Class Laboratory" do
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(Room.for_current_workspace.pluck(:rmrecnbr))
        .to contain_exactly("2005046", "2005047", "2005048", "2005090")
      expect(Room.for_current_workspace.pluck(:room_type))
        .to contain_exactly("Classroom", "Class Laboratory", "Office", "Classroom")

      expect(phase).to be_succeeded
      expect(phase.counters).to include("created" => 4, "api_calls" => 4, "rate_limit_sleeps" => 0)
      expect(counter(phase, :updated)).to eq(0)
    end

    it "denormalizes building_name, room_number, square_feet, room_type, and sets in_feed true" do
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)

      german = Room.for_current_workspace.find_by!(rmrecnbr: "2005046")
      expect(german.building).to eq(building_mlb)
      expect(german.building_name).to eq("Modern Languages Building")
      expect(german.room_number).to eq("1200")
      expect(german.square_feet).to eq(850)
      expect(german.room_type).to eq("Classroom")
      expect(german.in_feed).to be true
    end
  end

  describe "floor_id (D10)" do
    it "creates a floor once per (building, label) and links each room to it" do
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)

      expect(Floor.for_current_workspace.count).to eq(4)
      german = Room.for_current_workspace.find_by!(rmrecnbr: "2005046")
      expect(german.floor.label).to eq("1")
      expect(german.floor.building).to eq(building_mlb)
    end

    # normalize_floor_label teeth: the Office row's raw FloorNumber is "03"
    # (see rooms_1005046.json), not an already-normalized "3" — this fails
    # if the leading zero is ever passed through unstripped.
    it "strips a leading zero off FloorNumber via normalize_floor_label" do
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)

      office = Room.for_current_workspace.find_by!(rmrecnbr: "2005048")
      expect(office.floor.label).to eq("3")
    end

    it "reuses the same floor across runs instead of creating a duplicate" do
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)
      floor_id_before = Room.for_current_workspace.find_by!(rmrecnbr: "2005046").floor_id

      described_class.call(run: run, client: client)

      expect(Floor.for_current_workspace.count).to eq(4)
      expect(Room.for_current_workspace.find_by!(rmrecnbr: "2005046").floor_id).to eq(floor_id_before)
    end
  end

  describe "unit_id (Brief §14.1) — blank department group means admin-only, no unit" do
    it "leaves unit_id nil for a room with a blank department group" do
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)

      office = Room.for_current_workspace.find_by!(rmrecnbr: "2005048")
      expect(office.room_type).to eq("Office")
      expect(office.department_id).to be_nil
      expect(office.unit_id).to be_nil
    end

    # THE keying teeth (product-owner-confirmed): a Unit is keyed on the
    # STABLE department-group CODE (DeptGroup "COLLEGE_OF_LSA"), NOT the
    # free-text description. departments.json deliberately gives "LSA -
    # Mathematics" a REWORDED DeptGroupDescription ("College of Lit, Science
    # & Arts") while "LSA - German" (bulk) and "LSA - Chemistry" (via
    # fallback) keep the full "College of Literature, Science & the Arts" —
    # same code, three source rows, TWO distinct descriptions. Under
    # description-keying this forks into 2+ Units and this example fails;
    # under code-keying all three rooms collapse to ONE Unit.
    it "collapses departments sharing a group CODE into one Unit even when their descriptions differ" do
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)

      german = Room.for_current_workspace.find_by!(rmrecnbr: "2005046")
      chem_lab = Room.for_current_workspace.find_by!(rmrecnbr: "2005047")
      math = Room.for_current_workspace.find_by!(rmrecnbr: "2005090")

      expect(Unit.for_current_workspace.count).to eq(1)
      unit = Unit.for_current_workspace.sole
      expect(unit.department_group).to eq("COLLEGE_OF_LSA")
      expect([ german.unit_id, chem_lab.unit_id, math.unit_id ]).to all(eq(unit.id))
    end

    # A UnitDisplayName override keyed on the group CODE only fires if the
    # sync-created Unit is itself keyed on that CODE. Under the old
    # description-keying the Unit's department_group held the free text, the
    # override (keyed "COLLEGE_OF_LSA") never matched, and display_name
    # silently fell through to the raw description — a dead override. This
    # pins that the override now resolves.
    it "lets a code-keyed UnitDisplayName override drive the created Unit's display_name" do
      create(:unit_display_name, workspace: workspace, department_group: "COLLEGE_OF_LSA", display_name: "LSA")
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)

      unit = Unit.for_current_workspace.find_by!(department_group: "COLLEGE_OF_LSA")
      expect(unit.display_name).to eq("LSA")
    end
  end

  describe "department enrichment — bulk preload + per-id fallback" do
    it "enriches a room whose department id is in the bulk preload" do
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)

      math = Room.for_current_workspace.find_by!(rmrecnbr: "2005090")
      expect(math.department_id).to eq("180000")
      expect(math.department_description).to eq("LSA - Mathematics")
      expect(math.department_group).to eq("COLLEGE_OF_LSA")
      expect(math.department_group_description).to eq("College of Lit, Science & Arts")
    end

    it "falls back to a per-department fetch when a room's dept id is missing from the preload" do
      stub_departments_feed
      fallback_stub = stub_department_fallback
      stub_rooms_feed

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      chem_lab = Room.for_current_workspace.find_by!(rmrecnbr: "2005047")
      expect(chem_lab.department_id).to eq("190100")
      expect(chem_lab.department_description).to eq("LSA - Chemistry")
      expect(chem_lab.department_group_description).to eq("College of Literature, Science & the Arts")
      expect(fallback_stub).to have_been_requested.once
    end

    # THE performance teeth (Task 8's review flagged per-row Campus lookups
    # in UpdateBuildings): the preload is requested exactly ONCE for the
    # whole run. Department ids "190000" and "180000" are deliberately NOT
    # stubbed as individual per-id endpoints — if the implementation ever
    # regressed to a per-room fetch for an id that's already in the preload,
    # WebMock's disable_net_connect! would raise on that unstubbed request
    # and this example would fail.
    it "requests the department preload endpoint exactly once for the whole run" do
      preload_stub = stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(preload_stub).to have_been_requested.once
    end
  end

  describe "a second run with one changed field" do
    it "updates only the changed room, counts it, and leaves the others alone" do
      # A hand-rolled pre-existing row would also need to replicate every
      # derived field (floor, unit, department enrichment) the phase itself
      # computes, or changed_after_assign would flag every room as changed
      # for the wrong reason. Running the phase for real once establishes an
      # exact baseline, then a single field is mutated out from under it —
      # the only genuine change the second run should detect.
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed
      described_class.call(run: run, client: client)
      Room.for_current_workspace.find_by!(rmrecnbr: "2005046").update!(square_feet: 1)

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(Room.for_current_workspace.find_by!(rmrecnbr: "2005046").square_feet).to eq(850)
      expect(counter(phase, :created)).to eq(0)
      expect(phase.counters).to include("updated" => 1)
    end
  end

  describe "idempotency" do
    it "reports 0 created/updated/deactivated on a second run against the same feed" do
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)
      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(counter(phase, :created)).to eq(0)
      expect(counter(phase, :updated)).to eq(0)
      expect(counter(phase, :deactivated)).to eq(0)
      expect(Room.for_current_workspace.count).to eq(4)
    end
  end

  describe "deactivation sweep (Brief §6.1 phase 3 / §8.4 — deactivate, never delete)" do
    it "deactivates a pre-existing room absent from every building's feed" do
      absent = create(:room, workspace: workspace, building: building_mlb, rmrecnbr: "9999999", in_feed: true)
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(absent.reload.in_feed).to be false
      expect(phase.counters).to include("deactivated" => 1)
    end

    it "reactivates a room that reappears in the feed" do
      reappearing = create(:room, workspace: workspace, building: building_mlb, rmrecnbr: "2005046", in_feed: false)
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)

      expect(reappearing.reload.in_feed).to be true
    end

    # THE resilience-critical teeth: a real failure partway through the
    # sweep must roll back EVERY deactivation in the batch, not just the one
    # that raised. stale_first is created (and would be processed) BEFORE
    # stale_second (find_each walks in id order), so if the transaction
    # didn't wrap the whole loop, stale_first would show in_feed: false
    # (already committed) while stale_second raised — exactly the
    # half-deactivated state Brief §6.1's "all-or-nothing" rules out.
    it "rolls back every deactivation in the batch when one raises mid-sweep" do
      stale_first = create(:room, workspace: workspace, building: building_mlb, rmrecnbr: "9999001", in_feed: true)
      stale_second = create(:room, workspace: workspace, building: building_mlb, rmrecnbr: "9999002", in_feed: true)
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      deactivation_calls = 0
      allow_any_instance_of(Room).to receive(:update!).and_wrap_original do |method, *args|
        if args.first == { in_feed: false }
          deactivation_calls += 1
          raise "boom mid-deactivation" if deactivation_calls == 2
        end
        method.call(*args)
      end

      result = described_class.call(run: run, client: client)

      expect(result).not_to be_success
      expect(stale_first.reload.in_feed).to be true
      expect(stale_second.reload.in_feed).to be true
    end

    it "skips the sweep and warns instead of deactivating every room when every building's feed returns zero rows" do
      untouched = create(:room, workspace: workspace, building: building_mlb, rmrecnbr: "9999003", in_feed: true)
      stub_departments_feed
      stub_um_get("/bf/Buildings/v2/RoomInfo/1005046", fixture: "rooms_empty.json",
        query: { "$start_index" => "0", "$count" => "1000" })
      stub_um_get("/bf/Buildings/v2/RoomInfo/1005090", fixture: "rooms_empty.json",
        query: { "$start_index" => "0", "$count" => "1000" })

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(phase).to be_succeeded
      expect(untouched.reload.in_feed).to be true
      expect(counter(phase, :deactivated)).to eq(0)
      expect(phase.warnings).to include(a_string_matching(/zero rows/i))
    end
  end

  describe "D6: hidden_at is never touched by this phase" do
    it "leaves a hidden room's hidden_at intact when it is deactivated" do
      hidden = create(:room, :hidden, workspace: workspace, building: building_mlb, rmrecnbr: "9999004", in_feed: true)
      original_hidden_at = hidden.hidden_at
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)

      reloaded = hidden.reload
      expect(reloaded.in_feed).to be false
      expect(reloaded.hidden_at).to be_within(1.second).of(original_hidden_at)
    end

    it "leaves a hidden room's hidden_at intact when it reactivates" do
      hidden = create(:room, :hidden, workspace: workspace, building: building_mlb, rmrecnbr: "2005046", in_feed: false)
      original_hidden_at = hidden.hidden_at
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      described_class.call(run: run, client: client)

      reloaded = hidden.reload
      expect(reloaded.in_feed).to be true
      expect(reloaded.hidden_at).to be_within(1.second).of(original_hidden_at)
    end
  end

  describe "dry run (Brief §6.1 API_UPDATE_DELETE_DRY_RUN)" do
    it "does not deactivate but records the count and warns with the rmrecnbr" do
      dry_run = create(:sync_run, workspace: workspace, dry_run: true)
      stale = create(:room, workspace: workspace, building: building_mlb, rmrecnbr: "9999005", in_feed: true)
      stub_departments_feed
      stub_department_fallback
      stub_rooms_feed

      result = described_class.call(run: dry_run, client: client)

      expect(result).to be_success
      expect(stale.reload.in_feed).to be true

      dry_phase = dry_run.sync_phases.find_by!(key: "rooms")
      expect(dry_phase.counters).to include("deactivated" => 1)
      expect(counter(dry_phase, :created)).to eq(4)
      expect(dry_phase.warnings).to include(a_string_matching(/9999005/))
    end
  end
end
