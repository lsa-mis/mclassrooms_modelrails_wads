require "rails_helper"

RSpec.describe LegacyImport::BuildingMedia do
  include_context "legacy export"

  let(:workspace) { create(:workspace, personal: false) }
  let(:actor) { create(:user) }
  let!(:building) { create(:building, workspace:, bldrecnbr: "1000054", name: "EAST QUADRANGLE") }

  around { |example| Current.set(workspace:) { example.run } }

  def call(dry_run: false) = described_class.call(export: legacy_export, workspace:, actor:, dry_run:)

  def photo(fixture = "avatar.png", record_id: 1_000_054)
    export_tree.media(model: "Building", record_id:, attachment_name: "building_image", fixture:, record_label: "EAST QUADRANGLE")
  end

  def plan(label, building_name: "EAST QUADRANGLE")
    export_tree.media(model: "Floor", record_id: 7, attachment_name: "floor_plan", fixture: "room.jpg",
                      record_label: "#{building_name} floor #{label}")
  end

  def attach_photo(fixture)
    building.photo.attach(io: file_fixture(fixture).open, filename: fixture)
  end

  it "attaches a building photo and writes one audit row" do
    photo

    result = call

    expect(building.reload.photo).to be_attached
    expect(Digest::MD5.base64digest(building.photo.download)).to eq(Digest::MD5.base64digest(file_fixture("avatar.png").binread))
    expect(result.payload[:counters]).to include(created: 1)
    expect(ActivityLog.where(action: "building.legacy_imported", trackable: building).count).to eq(1)
  end

  it "skips a byte-identical photo" do
    attach_photo("avatar.png")
    photo

    result = call

    expect(result.payload[:counters]).to include(skipped: 1, created: 0, replaced: 0)
  end

  it "replaces a different photo and flags its authored alt for review" do
    attach_photo("equirect.png")
    photo("avatar.png")

    result = call

    expect(Digest::MD5.base64digest(building.reload.photo.download)).to eq(Digest::MD5.base64digest(file_fixture("avatar.png").binread))
    expect(result.payload[:replaced_lines]).to contain_exactly(a_string_ending_with("\tAUTHORED ALT — review"))
  end

  it "attaches a floor plan by building name and normalized label, and never creates a floor" do
    ground = create(:floor, building:, label: "G")
    plan("0G")

    expect { call }.not_to change(Floor, :count)

    expect(ground.reload.plan).to be_attached
  end

  it "reports a floor plan whose floor does not exist" do
    plan("09")

    result = nil
    expect { result = call }.not_to change(Floor, :count)

    expect(result.payload[:unmatched_lines]).to contain_exactly(a_string_starting_with("Floor\t7\tEAST QUADRANGLE floor 09"))
  end

  it "refuses a floor plan whose building name is ambiguous" do
    create(:building, workspace:, name: "EAST QUADRANGLE")
    create(:floor, building:, label: "1")
    plan("01")

    result = call

    expect(result.payload[:unmatched_lines]).to contain_exactly(a_string_ending_with("\tambiguous building name"))
  end

  it "reports a photo whose building is not in this workspace" do
    photo(record_id: 1_999_999)

    result = call

    expect(result.payload[:unmatched_lines]).to contain_exactly(a_string_starting_with("Building\t1999999"))
  end

  it "records a missing file as an error and carries on" do
    second = create(:building, workspace:, bldrecnbr: "1000055", name: "WEST HALL")
    photo
    export_tree.media(model: "Building", record_id: 1_000_055, attachment_name: "building_image", fixture: "avatar.png", record_label: "WEST HALL")
    export = legacy_export
    export_tree.remove(File.join("media", export.media("Building").first["path"]))

    result = described_class.call(export:, workspace:, actor:, dry_run: false)

    expect(result.payload[:error_lines]).to contain_exactly(a_string_including("not found"))
    expect(building.reload.photo).not_to be_attached
    expect(second.reload.photo).to be_attached
  end

  it "attaches nothing on dry run" do
    photo

    result = call(dry_run: true)

    expect(building.reload.photo).not_to be_attached
    expect(result.payload[:counters]).to include(created: 1)
  end
end
