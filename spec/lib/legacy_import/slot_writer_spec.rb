require "rails_helper"

RSpec.describe LegacyImport::SlotWriter do
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
