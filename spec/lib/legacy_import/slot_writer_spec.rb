require "rails_helper"

RSpec.describe LegacyImport::SlotWriter do
  include_context "legacy export"

  describe ".attachable" do
    let(:export) do
      export_tree.media(model: "Room", record_id: 2_000_001, attachment_name: "room_image", fixture: "avatar.png")
      legacy_export
    end
    let(:entry) { export.media("Room").first }

    it "returns the attachable hash for a file matching the manifest checksum" do
      expect(described_class.attachable(export, entry)).to include(filename: "avatar.png", content_type: "image/png")
    end

    it "raises Mismatch for a file whose bytes changed after the manifest was written" do
      export
      FileUtils.cp(file_fixture("room.jpg"), export.file(entry["path"]))

      expect { described_class.attachable(export, entry) }
        .to raise_error(LegacyImport::Export::Mismatch, /avatar\.png does not match the manifest checksum/)
    end
  end

  it "creates when nothing is attached, skips an identical file, replaces a different one" do
    expect(described_class.outcome(nil, "abc")).to eq(:created)
    expect(described_class.outcome("abc", "abc")).to eq(:skipped)
    expect(described_class.outcome("xyz", "abc")).to eq(:replaced)
  end

  it "flags a replaced image whose alt text was written by a person" do
    entry = { "model" => "Building", "record_id" => 1, "record_label" => "Mason", "attachment_name" => "building_image", "path" => "b/1.jpg" }

    expect(described_class.replaced_line(build(:building, photo_alt: "Front steps"), "photo_alt", entry)).to end_with("\tAUTHORED ALT — review")
    expect(described_class.replaced_line(build(:building, photo_alt: nil), "photo_alt", entry)).to eq(LegacyImport::Export.describe(entry))
  end
end
