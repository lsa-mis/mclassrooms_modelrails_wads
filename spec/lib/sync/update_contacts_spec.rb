require "rails_helper"

# Task 11 (phase B) of planning/plans/phase-2-ingestion.md: Sync::UpdateContacts
# is the second lightweight per-classroom phase (Brief §6.1 phase 6). It
# shares Sync::UpdateCharacteristics's per-room fetch shape (one API call
# per facility-coded room, each wrapped individually in
# client.rate_limiter.backoff_429) but there is nothing to diff — a room has
# at most ONE RoomContact (`has_one`, unique room_id, phase 1), so this
# phase is a plain upsert of the scheduling_*/support_* attribute blocks.
#
# contacts_MLB1200.json (Task 2 fixture) already has one field the gateway
# sent back as a JSON `null` (SupportPhone); contacts_AH0100.json (added
# here) additionally sends an explicit empty string (SchedEmail) and omits
# several keys entirely (SchedUsageGuidelinesUrl, SupportDeptDescr,
# SupportPhone, SupportUrl) — between the two fixtures every shape the
# gateway might use for "no value" is covered, and #parse_contact's
# `.presence` call must coerce all of them to nil, never "".
RSpec.describe Sync::UpdateContacts do
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

  def phase = run.sync_phases.find_by!(key: "contacts")

  # See update_campuses_spec.rb's identical helper: an untouched counter is
  # ABSENT from the hash, not present-and-zero, so #fetch(..., 0) has teeth
  # either way.
  def counter(phase, key) = phase.counters.fetch(key.to_s, 0)

  def stub_contacts(facility_code: "MLB1200", fixture: "contacts_MLB1200.json")
    stub_um_get("/bf/Buildings/v2/Classrooms/#{facility_code}/Contacts", fixture: fixture)
  end

  describe "upserting the room's single RoomContact" do
    it "creates a RoomContact with both the scheduling and support blocks" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      stub_contacts

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      contact = room.reload.room_contact
      expect(contact).to have_attributes(
        scheduling_name: "LSA Classroom Scheduling",
        scheduling_email: "lsa.scheduling@umich.edu",
        scheduling_phone: "734-555-0100",
        scheduling_detail_url: "https://lsa.umich.edu/classrooms/mlb1200",
        scheduling_usage_guidelines_url: "https://lsa.umich.edu/classrooms/guidelines",
        support_department_id: "190000",
        support_department_description: "LSA Technology Services",
        support_email: "lsa.support@umich.edu",
        support_url: "https://lsa.umich.edu/support"
      )
      expect(phase.counters).to include("updated" => 1, "api_calls" => 1, "rate_limit_sleeps" => 0)
    end

    it "updates the room's existing RoomContact in place rather than duplicating it" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      existing = create(:room_contact, workspace: workspace, room: room, scheduling_name: "Old Scheduling Office")
      stub_contacts

      described_class.call(run: run, client: client)

      expect(RoomContact.where(room: room).count).to eq(1)
      expect(existing.reload.scheduling_name).to eq("LSA Classroom Scheduling")
    end
  end

  describe %(absent fields coerce to nil, never "") do
    it "stores nil for a JSON null field" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      stub_contacts

      described_class.call(run: run, client: client)

      expect(room.reload.room_contact.support_phone).to be_nil
    end

    it "stores nil for an explicit empty string, and for keys omitted entirely" do
      room = create(:room, workspace: workspace, building: building, facility_code: "AH0100")
      stub_contacts(facility_code: "AH0100", fixture: "contacts_AH0100.json")

      described_class.call(run: run, client: client)

      contact = room.reload.room_contact
      expect(contact.scheduling_email).to be_nil
      expect(contact.scheduling_email).not_to eq("")
      expect(contact.scheduling_usage_guidelines_url).to be_nil
      expect(contact.support_department_description).to be_nil
      expect(contact.support_phone).to be_nil
      expect(contact.support_url).to be_nil
      # Fields that WERE present on this fixture still come through untouched.
      expect(contact.scheduling_name).to eq("Angell Hall Scheduling")
      expect(contact.support_department_id).to eq("190000")
    end
  end

  describe "only facility-coded rooms are fetched" do
    it "never requests the endpoint for a room without a facility_code" do
      create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      create(:room, workspace: workspace, building: building, facility_code: nil)
      stub_contacts

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(phase.counters).to include("api_calls" => 1)
    end
  end

  describe "idempotency" do
    it "reports 0 updated on a second run against unchanged data" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      stub_contacts

      described_class.call(run: run, client: client)
      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(counter(phase, :updated)).to eq(0)
      expect(RoomContact.where(room: room).count).to eq(1)
    end
  end

  describe "per-room 429 retry (Brief §6.1 phase 4)" do
    it "retries after a transient 429 from a room's contacts endpoint and still succeeds" do
      room = create(:room, workspace: workspace, building: building, facility_code: "MLB1200")
      url = "#{UmApiStubs::DEFAULT_BASE_URL}/bf/Buildings/v2/Classrooms/MLB1200/Contacts"
      stub_request(:get, url).to_return(
        { status: 429, body: "" },
        { status: 200, headers: UmApiStubs::JSON_RESPONSE_HEADERS, body: um_api_fixture("contacts_MLB1200.json") }
      )

      result = described_class.call(run: run, client: client)

      expect(result).to be_success
      expect(room.reload.room_contact.scheduling_name).to eq("LSA Classroom Scheduling")
      expect(counter(phase, :rate_limit_sleeps)).to eq(1)
    end
  end
end
