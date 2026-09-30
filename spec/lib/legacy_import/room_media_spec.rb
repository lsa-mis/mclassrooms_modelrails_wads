require "rails_helper"

RSpec.describe LegacyImport::RoomMedia do
  include_context "legacy export"
  include ActiveJob::TestHelper

  let(:workspace) { create(:workspace, personal: false) }
  let!(:actor) { create(:user) }
  let(:building) { create(:building, workspace:) }
  let!(:room) { create(:room, building:, rmrecnbr: "2196067") }

  before { clear_enqueued_jobs }

  around { |example| Current.set(workspace:) { example.run } }

  def call(dry_run: false) = described_class.call(export: legacy_export, workspace:, actor:, dry_run:)

  def media(attachment_name, fixture, filename: nil, record_id: 2_196_067)
    export_tree.media(model: "Room", record_id:, attachment_name:, fixture:, filename: filename || File.basename(fixture))
  end

  def md5(io_or_bytes) = Digest::MD5.base64digest(io_or_bytes)

  it "attaches panorama, seating chart and gallery in one audited transaction" do
    media("room_panorama", "room.jpg")
    media("room_layout", "seating_chart.pdf")
    media("room_image", "avatar.png", filename: "PHARM 1300 Image 1 2026.jpeg")
    media("gallery_image1", "equirect.png", filename: "PHARM 1300 Image 2 2026.jpeg")

    result = call

    room.reload
    expect(room.panorama).to be_attached
    expect(room.seating_chart).to be_attached
    expect(room.gallery.map { |asset| [ asset.position, asset.subject, asset.image_alt ] }).to eq([ [ 1, nil, nil ], [ 2, nil, nil ] ])
    expect(result.payload[:counters]).to include(created: 4)
    expect(result.payload[:info_lines]).to eq([ "gallery positions: 2 from filenames, 0 from slots" ])
    expect(ActivityLog.where(action: "room.legacy_imported", trackable: room).count).to eq(1)
    expect(RenderFlatPanoramaJob).to have_been_enqueued.with(room.id)
  end

  it "skips everything on a second run" do
    media("room_panorama", "room.jpg")
    media("room_image", "avatar.png")
    call

    result = call

    expect(result.payload[:counters]).to include(created: 0, replaced: 0, skipped: 2)
  end

  it "replaces a different still but keeps the alt text and subject a person chose" do
    create(:media_asset, owner: room, position: 1, subject: "front", image_alt: "Lectern and screen")
    media("room_image", "equirect.png")

    result = call

    asset = room.reload.gallery.sole
    expect(md5(asset.image.download)).to eq(md5(file_fixture("equirect.png").binread))
    expect(asset).to have_attributes(subject: "front", image_alt: "Lectern and screen")
    expect(result.payload[:replaced_lines]).to contain_exactly(a_string_ending_with("\tAUTHORED ALT — review"))
  end

  it "replaces a different panorama and reports it" do
    room.panorama.attach(io: file_fixture("equirect.png").open, filename: "old.png")
    media("room_panorama", "room.jpg")

    result = call

    expect(md5(room.reload.panorama.download)).to eq(md5(file_fixture("room.jpg").binread))
    expect(result.payload[:counters]).to include(replaced: 1)
  end

  # stray.txt keeps its .txt name so it identifies as text/plain; renamed to
  # .jpg, Marcel would fall back to the extension and the panorama would pass.
  it "rolls back a room whose file is rejected and imports the others" do
    other = create(:room, building:, rmrecnbr: "2196068")
    media("room_image", "avatar.png")
    media("room_panorama", "stray.txt")
    media("room_image", "avatar.png", record_id: 2_196_068)

    result = call

    expect(result.payload[:error_lines]).to contain_exactly(a_string_starting_with("Room\t2196067"))
    expect(room.reload.gallery).to be_empty
    expect(room.panorama).not_to be_attached
    expect(other.reload.gallery.size).to eq(1)
  end

  it "retries a failed room on the next run and skips the rooms that finished" do
    other = create(:room, building:, rmrecnbr: "2196068")
    media("room_image", "avatar.png")
    media("room_panorama", "room.jpg")
    media("room_image", "avatar.png", record_id: 2_196_068)
    panorama_path = Pathname(@legacy_export_root).join("media/room/2196067/room_panorama/room.jpg")
    panorama_path.delete

    first = call
    FileUtils.cp(file_fixture("room.jpg"), panorama_path)
    second = call

    expect(first.payload[:error_lines]).to contain_exactly(a_string_including("not found"))
    expect(second.payload[:error_lines]).to be_empty
    expect(second.payload[:counters]).to include(created: 2, skipped: 1)
    expect(room.reload.panorama).to be_attached
    expect(other.reload.gallery.size).to eq(1)
  end

  it "reports rooms that are not in this workspace and leaves another workspace's room alone" do
    elsewhere = create(:room, building: create(:building))
    media("room_image", "avatar.png", record_id: elsewhere.rmrecnbr.to_i)
    media("room_image", "avatar.png", record_id: 9_999_999)

    result = nil
    expect { result = call }.not_to change(MediaAsset, :count)

    expect(result.payload[:unmatched_lines].size).to eq(2)
  end

  it "writes nothing on dry run" do
    media("room_panorama", "room.jpg")
    media("room_image", "avatar.png")

    result = nil
    expect { result = call(dry_run: true) }.not_to change { [ MediaAsset.count, ActiveStorage::Attachment.count, ActivityLog.count ] }

    expect(result.payload[:counters]).to include(created: 2)
  end
end
