require "rails_helper"

# Task 11 (phase A) of planning/plans/phase-2-ingestion.md: Sync::UpdateCharacteristics
# is the first of the two lightweight PER-CLASSROOM phases (Brief §6.1 phase
# 5). Unlike every earlier phase, there is no bulk listing endpoint here —
# the gateway exposes one classroom's characteristics at a time, keyed by
# facility_code, so this phase makes ONE API call per facility-coded room
# and wraps each individually in client.rate_limiter.backoff_429 (mirroring
# Sync::UpdateRooms's #fetch_department_fallback per-item retry, NOT
# Sync::UpdateFacilityIds's whole-walk retry — there is no single walk here
# to wrap).
#
# The crux this file pins is the PER-ROOM diff: create codes present in the
# room's response but missing from the DB, delete codes present in the DB
# but missing from the response — including deleting every existing row
# when the response is empty, since an empty response for ONE room means
# that room legitimately has zero characteristics (not the whole-table
# empty-feed footgun Task 7-10's stale sweeps guard against).
#
# characteristics_MLB1200.json (Task 2 fixture) carries three characteristics:
# INSTRCOMP/InstrComp, LECTURECAP/LectureCap, WHTBD25/"Whtbrd>25" — the last
# one deliberately has a non-alphanumeric short code so the normalization
# rule (Brief §6.1 phase 5, phase-1's Room.normalize_facility_code
# transform: downcase + strip non-[a-z0-9]) has real teeth: "Whtbrd>25" ->
# "whtbrd25".
RSpec.describe Sync::UpdateCharacteristics do
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
  # No-op sleeper, exactly like update_facility_ids_spec.rb's rationale: the
  # 429-retry example below would otherwise really sleep 61s.
  let(:client) { UmApi::Client.new(rate_limiter: UmApi::RateLimiter.new(sleeper: ->(_seconds) { })) }
  let!(:building) { create(:building, workspace: workspace) }

  before do
    Current.workspace = workspace
    stub_um_token(scope: "classrooms")
  end

  def phase = run.sync_phases.find_by!(key: "characteristics")

  # See update_campuses_spec.rb's identical helper: an untouched counter is
  # ABSENT from the hash, not present-and-zero, so #fetch(..., 0) has teeth
  # either way.
  def counter(phase, key) = phase.counters.fetch(key.to_s, 0)

  def stub_characteristics(facility_code: "MLB1200", fixture: "characteristics_MLB1200.json")
    stub_um_get("/bf/Buildings/v2/Classrooms/#{facility_code}/Characteristics", fixture: fixture)
  end

  describe "per-room diff" do
    it "creates every characteristic missing from the room" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      stub_characteristics

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(room.room_characteristics.pluck(:code)).to contain_exactly("INSTRCOMP", "LECTURECAP", "WHTBD25")
      expect(phase.counters).to include("added" => 3, "api_calls" => 1, "rate_limit_sleeps" => 0)
      expect(counter(phase, :removed)).to eq(0)
    end

    it "deletes a pre-existing characteristic absent from the room's response" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      departed = create(:room_characteristic, workspace: workspace, room: room, code: "OLDCODE", short_code: "Old")
      stub_characteristics

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(RoomCharacteristic.exists?(departed.id)).to be false
      expect(room.room_characteristics.pluck(:code)).to contain_exactly("INSTRCOMP", "LECTURECAP", "WHTBD25")
      expect(phase.counters).to include("added" => 3, "removed" => 1)
    end

    it "deletes ALL of a room's characteristics when its response comes back empty" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      create(:room_characteristic, workspace: workspace, room: room, code: "INSTRCOMP", short_code: "InstrComp")
      create(:room_characteristic, workspace: workspace, room: room, code: "LECTURECAP", short_code: "LectureCap")
      stub_characteristics(fixture: "characteristics_empty.json")

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(room.room_characteristics.count).to eq(0)
      expect(counter(phase, :added)).to eq(0)
      expect(phase.counters).to include("removed" => 2)
    end

    it "leaves a matched characteristic untouched (no update, no re-save)" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      existing = create(:room_characteristic, workspace: workspace, room: room, code: "INSTRCOMP", short_code: "InstrComp")
      stub_characteristics

      described_class.call(run: run, client: client)

      expect(existing.reload.id).to eq(existing.id)
    end
  end

  describe "short-code normalization (Brief §6.1 phase 5)" do
    it "normalizes a non-alphanumeric short code to alphanumerics per the phase-1 rule" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      stub_characteristics

      described_class.call(run: run, client: client)

      whiteboard = room.room_characteristics.find_by!(code: "WHTBD25")
      expect(whiteboard.short_code).to eq("whtbrd25")
    end

    # A short code that is all-punctuation normalizes to blank (nil, via the
    # shared CodeNormalizer). Creating a RoomCharacteristic with a blank
    # short_code violates its presence validation and raises RecordInvalid —
    # UNRESCUED inside #perform's find_each loop, that would abort
    # characteristic sync for every SUBSEQUENT room in the run. This pins
    # that the unstorable row is skipped (not created), the room's OTHER
    # characteristics still sync, and a LATER room in the same run is
    # unaffected — the phase still succeeds.
    it "skips a row whose short code normalizes to blank without aborting the rest of the run" do
      room_a = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      room_b = create(:room, workspace: workspace, building: building, facility_code: "AH0100")
      stub_characteristics(facility_code: "MLB1200", fixture: "characteristics_with_blank.json")
      stub_characteristics(facility_code: "AH0100", fixture: "characteristics_MLB1200.json")

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(phase).to be_succeeded
      # room_a: the valid INSTRCOMP row synced, the blank BADCODE row skipped.
      # Query RoomCharacteristic directly (not room.room_characteristics.count
      # across two Room instances, which trips Bullet's counter-cache advice).
      expect(RoomCharacteristic.where(room: room_a).pluck(:code)).to contain_exactly("INSTRCOMP")
      # room_b (processed AFTER room_a) still synced fully — no abort.
      expect(RoomCharacteristic.where(room: room_b).count).to eq(3)
      expect(counter(phase, :skipped)).to eq(1)
    end
  end

  # Phase 3's CharacteristicFilterGroups joins RoomCharacteristic.short_code
  # (written by this sync) to CharacteristicDisplayRule.short_code (seeded /
  # admin-CRUD'd) BY short_code. Case-sensitive SQLite means an unnormalized
  # mismatch ("Whtbrd>25" vs "whtbrd25") makes every join miss. Both sides
  # now route through the shared CodeNormalizer, so the same raw input lands
  # on EQUAL stored values — this pins that the join will match.
  describe "phase-3 join correctness: sync and display-rule short codes converge" do
    it "writes a RoomCharacteristic.short_code equal to a CharacteristicDisplayRule built from the same raw short code" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      stub_characteristics

      described_class.call(run: run, client: client)

      rule = CharacteristicDisplayRule.create!(workspace: workspace, short_code: "Whtbrd>25")
      synced = room.room_characteristics.find_by!(code: "WHTBD25")
      expect(synced.short_code).to eq(rule.short_code)
      expect(synced.short_code).to eq("whtbrd25")
    end
  end

  describe "D14: writes touch updated_at so phase 3's derived cache version advances" do
    it "advances RoomCharacteristic.maximum(:updated_at) without any explicit cache-stamp write" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      travel_to(1.day.ago) do
        create(:room_characteristic, workspace: workspace, room: room, code: "OLDCODE", short_code: "Old")
      end
      stub_characteristics

      expect {
        described_class.call(run: run, client: client)
      }.to change { RoomCharacteristic.maximum(:updated_at) }

      # No cache-stamp bookkeeping (D14): phase 3's CharacteristicFilterGroups
      # derives its cache key from the RoomCharacteristic rows themselves, so
      # this phase never writes a Setting row of its own.
      expect(Setting.count).to eq(0)
    end
  end

  describe "idempotency" do
    it "reports 0 added/0 removed on a second run against the same response" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      stub_characteristics

      described_class.call(run: run, client: client)
      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(counter(phase, :added)).to eq(0)
      expect(counter(phase, :removed)).to eq(0)
      expect(room.room_characteristics.count).to eq(3)
    end
  end

  describe "only facility-coded rooms are fetched" do
    it "never requests the endpoint for a room without a facility_code" do
      create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      create(:room, workspace: workspace, building: building, facility_code: nil)
      stub_characteristics

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(phase.counters).to include("api_calls" => 1)
    end
  end

  describe "per-room 429 retry (Brief §6.1 phase 4)" do
    it "retries after a transient 429 from a room's characteristics endpoint and still succeeds" do
      create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      url = "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2/Classrooms/MLB1200/Characteristics"
      stub_request(:get, url).to_return(
        { status: 429, body: "" },
        { status: 200, headers: UmApiStubs::JSON_RESPONSE_HEADERS, body: um_api_fixture("characteristics_MLB1200.json") }
      )

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(RoomCharacteristic.count).to eq(3)
      expect(counter(phase, :rate_limit_sleeps)).to eq(1)
    end
  end
end
