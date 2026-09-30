require "rails_helper"

RSpec.describe LegacyImport::Export do
  include_context "legacy export"

  it "yields the manifest entries for one legacy model" do
    export_tree.media(model: "Room", record_id: 2_000_001, attachment_name: "room_panorama", fixture: "room.jpg")
               .media(model: "Building", record_id: 1_000_001, attachment_name: "building_image", fixture: "avatar.png")

    export = legacy_export

    expect(export.media("Room").map { |entry| entry["attachment_name"] }).to eq([ "room_panorama" ])
    expect(export.media("Floor")).to eq([])
  end

  it "parses each NDJSON row" do
    export_tree.row(:rooms, rmrecnbr: "2000123", nickname: "Aud 3")

    expect(legacy_export.rows(:rooms)).to eq([ { "rmrecnbr" => "2000123", "nickname" => "Aud 3" } ])
  end

  it "resolves a manifest path to the file's bytes" do
    export_tree.media(model: "Room", record_id: 2_000_001, attachment_name: "room_image", fixture: "avatar.png")
    export = legacy_export

    path = export.file(export.media("Room").first["path"])

    expect(path.binread).to eq(file_fixture("avatar.png").binread)
  end

  it "raises Missing for a listed file that is not on disk" do
    export_tree.media(model: "Room", record_id: 2_000_001, attachment_name: "room_image", fixture: "avatar.png")
    export = legacy_export
    entry = export.media("Room").first
    export_tree.remove(File.join("media", entry["path"]))

    expect { export.file(entry["path"]) }.to raise_error(described_class::Missing, /avatar\.png not found/)
  end

  it "raises Missing when the media manifest is absent" do
    expect { described_class.new(@legacy_export_root) }.to raise_error(described_class::Missing, /manifest\.json not found/)
  end

  it "raises Missing for an absent data file" do
    export = legacy_export
    export_tree.remove("curated/data/notes.ndjson")

    expect { export.rows(:notes) }.to raise_error(described_class::Missing, /notes\.ndjson not found/)
  end

  it "describes an entry as one tab-separated report line" do
    entry = { "model" => "Room", "record_id" => 2_000_001, "record_label" => "MLB 1200",
              "attachment_name" => "room_image", "path" => "room/x.jpg" }

    expect(described_class.describe(entry)).to eq("Room\t2000001\tMLB 1200\troom_image\troom/x.jpg")
  end
end
