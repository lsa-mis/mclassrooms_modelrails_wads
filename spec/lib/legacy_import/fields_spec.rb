require "rails_helper"

RSpec.describe LegacyImport::Fields do
  include_context "legacy export"

  let(:workspace) { create(:workspace, personal: false) }
  let!(:actor) { create(:user) }
  let!(:building) { create(:building, workspace:, bldrecnbr: "1005058", nickname: nil, latitude: nil, longitude: nil) }
  let!(:room) { create(:room, building:, rmrecnbr: "2000123", nickname: nil, ada_seat_count: nil) }

  around { |example| Current.set(workspace:) { example.run } }

  it "fills blank curated room and building columns" do
    export_tree.row(:rooms, rmrecnbr: "2000123", nickname: "Aud 3", ada_seat_count: 4, visible: true)
               .row(:buildings, bldrecnbr: "1005058", nickname: "MLB", latitude: 42.2765, longitude: -83.7397, visible: true)

    result = run_importer

    expect(room.reload).to have_attributes(nickname: "Aud 3", ada_seat_count: 4, hidden_at: nil)
    expect(building.reload).to have_attributes(nickname: "MLB", latitude: BigDecimal("42.2765"), longitude: BigDecimal("-83.7397"))
    expect(result.payload[:counters]).to include(updated: 2)
    expect(ActivityLog.where(action: "room.legacy_imported", trackable: room)).to exist
  end

  it "never overwrites a value the new app already holds" do
    room.update!(nickname: "Kept")
    export_tree.row(:rooms, rmrecnbr: "2000123", nickname: "Legacy", visible: true)

    result = run_importer

    expect(room.reload.nickname).to eq("Kept")
    expect(result.payload[:counters]).to include(skipped: 1, updated: 0)
  end

  it "hides a room the legacy app hid, crediting the import account" do
    export_tree.row(:rooms, rmrecnbr: "2000123", visible: false)

    run_importer

    expect(room.reload.hidden_at).to be_present
    expect(room.hidden_by).to eq(actor)
  end

  it "does not hide a room the sync no longer lists" do
    room.update!(in_feed: false)
    export_tree.row(:rooms, rmrecnbr: "2000123", visible: false)

    run_importer

    expect(room.reload.hidden_at).to be_nil
  end

  it "leaves every sync-owned column as it was" do
    sync_owned = %w[room_number room_type instructional_seat_count in_feed building_id floor_id unit_id campus_id facility_code]
    before = room.attributes.slice(*sync_owned)
    export_tree.row(:rooms, rmrecnbr: "2000123", nickname: "Aud 3", ada_seat_count: 4, visible: false,
                            room_number: "9999", instructional_seat_count: 1)

    run_importer

    expect(room.reload.attributes.slice(*sync_owned)).to eq(before)
  end

  it "reports rows whose record is not in this workspace, and leaves another workspace's room alone" do
    other = create(:room, building: create(:building), nickname: nil)
    export_tree.row(:rooms, rmrecnbr: other.rmrecnbr, nickname: "Elsewhere", visible: true)
               .row(:rooms, rmrecnbr: "9999999", nickname: "Gone", visible: true)
               .row(:buildings, bldrecnbr: "1999999", nickname: "Gone", visible: true)

    result = run_importer

    expect(result.payload[:unmatched_lines]).to contain_exactly("Room\t#{other.rmrecnbr}", "Room\t9999999", "Building\t1999999")
    expect(other.reload.nickname).to be_nil
  end

  it "counts but writes nothing on dry run" do
    export_tree.row(:rooms, rmrecnbr: "2000123", nickname: "Aud 3", visible: false)

    result = nil
    expect { result = run_importer(dry_run: true) }.not_to change(ActivityLog, :count)

    expect(room.reload).to have_attributes(nickname: nil, hidden_at: nil)
    expect(result.payload[:counters]).to include(updated: 1)
  end
end
