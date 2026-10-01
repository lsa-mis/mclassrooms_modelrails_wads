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

  def room_file(attachment_name, fixture, filename: nil, record_id: 2_196_067)
    export_tree.media(model: "Room", record_id:, attachment_name:, fixture:, filename: filename || File.basename(fixture))
  end

  def md5(io_or_bytes) = Digest::MD5.base64digest(io_or_bytes)

  it "attaches panorama, seating chart and gallery in one audited transaction" do
    room_file("room_panorama", "room.jpg")
    room_file("room_layout", "seating_chart.pdf")
    room_file("room_image", "avatar.png", filename: "PHARM 1300 Image 1 2026.jpeg")
    room_file("gallery_image1", "equirect.png", filename: "PHARM 1300 Image 2 2026.jpeg")

    result = run_importer

    room.reload
    expect(room.panorama).to be_attached
    expect(room.seating_chart).to be_attached
    expect(room.gallery.map { |asset| [ asset.position, asset.subject, asset.image_alt ] }).to eq([ [ 1, nil, nil ], [ 2, nil, nil ] ])
    expect(result.payload[:counters]).to include(created: 4)
    expect(result.payload[:info_lines]).to eq([ "gallery positions: 1 from filenames, 1 from slots" ])
    expect(ActivityLog.where(action: "room.legacy_imported", trackable: room).count).to eq(1)
    expect(RenderFlatPanoramaJob).to have_been_enqueued.with(room.id)
  end

  it "reports a file that no longer matches the manifest checksum and leaves the room unchanged" do
    room_file("room_panorama", "room.jpg")
    export = legacy_export
    FileUtils.cp(file_fixture("avatar.png"), export.file(export.media("Room").first["path"]))

    result = described_class.call(export:, workspace:, actor:, dry_run: false)

    expect(result.payload[:error_lines]).to contain_exactly(a_string_including("does not match the manifest checksum"))
    expect(room.reload.panorama).not_to be_attached
  end

  it "skips everything on a second run" do
    room_file("room_panorama", "room.jpg")
    room_file("room_image", "avatar.png")
    run_importer

    result = run_importer

    expect(result.payload[:counters]).to include(created: 0, replaced: 0, skipped: 2)
  end

  it "replaces a different still but keeps the alt text and subject a person chose" do
    create(:media_asset, owner: room, position: 1, subject: "front", image_alt: "Lectern and screen")
    room_file("room_image", "equirect.png")

    result = run_importer

    asset = room.reload.gallery.sole
    expect(md5(asset.image.download)).to eq(md5(file_fixture("equirect.png").binread))
    expect(asset).to have_attributes(subject: "front", image_alt: "Lectern and screen")
    expect(result.payload[:replaced_lines]).to contain_exactly(a_string_ending_with("\tAUTHORED ALT — review"))
  end

  it "replaces a different panorama and reports it" do
    room.panorama.attach(io: file_fixture("equirect.png").open, filename: "old.png")
    room_file("room_panorama", "room.jpg")

    result = run_importer

    expect(md5(room.reload.panorama.download)).to eq(md5(file_fixture("room.jpg").binread))
    expect(result.payload[:counters]).to include(replaced: 1)
  end

  # stray.txt keeps its .txt name so it identifies as text/plain; renamed to
  # .jpg, Marcel would fall back to the extension and the panorama would pass.
  it "rolls back a room whose file is rejected and imports the others" do
    other = create(:room, building:, rmrecnbr: "2196068")
    room_file("room_image", "avatar.png")
    room_file("room_panorama", "stray.txt")
    room_file("room_image", "avatar.png", record_id: 2_196_068)

    result = run_importer

    expect(result.payload[:error_lines]).to contain_exactly(a_string_starting_with("Room\t2196067"))
    expect(room.reload.gallery).to be_empty
    expect(room.panorama).not_to be_attached
    expect(other.reload.gallery.size).to eq(1)
  end

  it "retries a failed room on the next run and skips the rooms that finished" do
    other = create(:room, building:, rmrecnbr: "2196068")
    room_file("room_image", "avatar.png")
    room_file("room_panorama", "room.jpg")
    room_file("room_image", "avatar.png", record_id: 2_196_068)
    panorama_path = Pathname(@legacy_export_root).join("media/room/2196067/room_panorama/room.jpg")
    panorama_path.delete

    first = run_importer
    FileUtils.cp(file_fixture("room.jpg"), panorama_path)
    second = run_importer

    expect(first.payload[:error_lines]).to contain_exactly(a_string_including("not found"))
    expect(second.payload[:error_lines]).to be_empty
    expect(second.payload[:counters]).to include(created: 2, skipped: 1)
    expect(room.reload.panorama).to be_attached
    expect(other.reload.gallery.size).to eq(1)
  end

  it "reports rooms that are not in this workspace and leaves another workspace's room alone" do
    elsewhere = create(:room, building: create(:building))
    room_file("room_image", "avatar.png", record_id: elsewhere.rmrecnbr.to_i)
    room_file("room_image", "avatar.png", record_id: 9_999_999)

    result = nil
    expect { result = run_importer }.not_to change(MediaAsset, :count)

    expect(result.payload[:unmatched_lines].size).to eq(2)
  end

  it "writes nothing on dry run" do
    room_file("room_panorama", "room.jpg")
    room_file("room_image", "avatar.png")

    result = nil
    expect { result = run_importer(dry_run: true) }.not_to change { [ MediaAsset.count, ActiveStorage::Attachment.count, ActivityLog.count ] }

    expect(result.payload[:counters]).to include(created: 2)
  end
end
