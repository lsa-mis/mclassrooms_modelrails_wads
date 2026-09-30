require "rails_helper"

RSpec.describe LegacyImport::Runner do
  include_context "legacy export"

  let(:workspace) { create(:workspace, personal: false) }
  let!(:building) { create(:building, workspace:, bldrecnbr: "1000054", name: "EAST QUADRANGLE", nickname: nil) }
  let!(:floor) { create(:floor, building:, label: "1") }
  let!(:room) { create(:room, building:, rmrecnbr: "2196067", nickname: nil) }

  before do
    export_tree
      .media(model: "Building", record_id: 1_000_054, attachment_name: "building_image", fixture: "avatar.png")
      .media(model: "Floor", record_id: 3, attachment_name: "floor_plan", fixture: "room.jpg", record_label: "EAST QUADRANGLE floor 01")
      .media(model: "Room", record_id: 2_196_067, attachment_name: "room_panorama", fixture: "room.jpg")
      .media(model: "Room", record_id: 2_196_067, attachment_name: "room_image", fixture: "avatar.png")
      .row(:rooms, rmrecnbr: "2196067", nickname: "Pharm Aud", visible: true)
      .row(:buildings, bldrecnbr: "1000054", nickname: "East Quad", visible: true)
      .row(:notes, legacy_id: 1, parent_legacy_id: nil, notable_type: "Room", notable_key: "2196067",
                   author_email: "dcran@umich.edu", alert: true, body_html: "<p>Call first</p>",
                   created_at: "2022-02-24T19:01:26Z", updated_at: "2022-02-24T19:01:26Z")
      .row(:announcements, slot: "home_page", body_html: "<p>Welcome</p>")
  end

  def run(**opts) = described_class.call(export_path: export_tree.write!.to_s, workspace:, **opts)

  def sum(result, *outcomes) = result.payload[:results].values.sum { |r| r.payload[:counters].values_at(*outcomes).sum }

  it "imports every phase in order, crediting notes to the Legacy import account" do
    result = run

    expect(result).to be_success
    expect(result.payload[:results].keys).to eq(%w[Fields BuildingMedia RoomMedia Announcements Notes])
    expect(room.reload).to have_attributes(nickname: "Pharm Aud")
    expect(room.panorama).to be_attached
    expect(floor.reload.plan).to be_attached
    expect(Note.sole.author.email_address).to eq(LegacyImport::Account::EMAIL)
    expect(Announcement.for("home_page")).to be_present
  end

  it "only skips on a second run" do
    run

    expect(sum(run, :created, :updated, :replaced)).to eq(0)
  end

  it "never creates a room, building or floor and leaves sync-owned columns alone" do
    sync_owned = %w[room_number room_type instructional_seat_count in_feed building_id floor_id]
    before = room.attributes.slice(*sync_owned)

    expect { run }.not_to change { [ Room.count, Building.count, Floor.count ] }

    expect(room.reload.attributes.slice(*sync_owned)).to eq(before)
  end

  it "writes nothing on dry run, not even the import account" do
    snapshot = -> { [ ActiveStorage::Attachment.count, MediaAsset.count, Note.count, Announcement.count, ActivityLog.count, User.count ] }

    result = nil
    expect { result = run(dry_run: true) }.not_to change(&snapshot)

    expect(result).to be_success
    expect(sum(result, :created, :updated)).to be_positive
    expect(room.reload.nickname).to be_nil
  end

  it "runs only the named phases" do
    result = run(only: %w[notes])

    expect(result.payload[:results].keys).to eq(%w[Notes])
    expect(room.reload.panorama).not_to be_attached
  end

  it "fails before writing anything on an unknown phase" do
    result = nil
    expect { result = run(only: %w[note]) }.not_to change(User, :count)

    expect(result).not_to be_success
    expect(result.errors.first).to match(/unknown phase\(s\): note/)
  end

  it "fails on an empty workspace" do
    result = described_class.call(export_path: export_tree.write!.to_s, workspace: create(:workspace, personal: false))

    expect(result.errors.first).to match(/has no rooms or buildings/)
  end

  it "fails on a missing export" do
    result = described_class.call(export_path: "/nonexistent/export", workspace:)

    expect(result.errors.first).to match(/manifest\.json not found/)
  end
end
