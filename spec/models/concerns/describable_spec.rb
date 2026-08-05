require "rails_helper"

RSpec.describe Describable do
  # MediaAsset is the first real consumer (slot :image).
  subject(:record) { build(:media_asset, image_alt: nil, image_derived_ok: false) }

  describe "#alt_for" do
    it "returns the derived backstop when stored alt is blank" do
      expect(record.alt_for(:image)).to be_present
    end

    it "returns the stored alt when present" do
      record.image_alt = "Podium close-up, north wall"
      expect(record.alt_for(:image)).to eq("Podium close-up, north wall")
    end
  end

  describe "#description_for" do
    it "is nil when unauthored (no backstop)" do
      expect(record.description_for(:image)).to be_nil
    end

    it "returns the stored description" do
      record.image_description = "Shows the HDMI and USB-C inputs."
      expect(record.description_for(:image)).to eq("Shows the HDMI and USB-C inputs.")
    end
  end

  describe "#alt_status_for" do
    it "is :authored when stored alt present" do
      record.image_alt = "x"
      expect(record.alt_status_for(:image)).to eq(:authored)
    end

    it "is :derived_ok when flagged and alt blank" do
      record.image_derived_ok = true
      expect(record.alt_status_for(:image)).to eq(:derived_ok)
    end

    it "is :needs_review by default" do
      expect(record.alt_status_for(:image)).to eq(:needs_review)
    end
  end

  it "registers the including model" do
    # Force-load the class: RSpec always runs a group's own examples before
    # descending into nested `describe` blocks, so this top-level example
    # can't rely on the `record` subject in a sibling block having already
    # triggered autoload (and the resulting `describable` registration).
    MediaAsset
    expect(Describable.registry.values).to include(MediaAsset)
  end
end

RSpec.describe "Describable slot declarations" do
  it "declares building photo with a non-blank backstop" do
    b = build(:building, name: "Mason Hall", photo_alt: nil)
    expect(b.alt_for(:photo)).to be_present
  end

  it "declares floor plan with a non-blank backstop" do
    f = build(:floor, plan_alt: nil)
    expect(f.alt_for(:plan)).to be_present
  end

  # Two, not three: Room's stills moved to Room#gallery (MediaAsset), which
  # declares its own :image slot — Room has no :photo slot to describe.
  it "declares both room slots with non-blank backstops" do
    r = build(:room, panorama_alt: nil, seating_chart_alt: nil)
    expect(r.alt_for(:panorama)).to be_present
    expect(r.alt_for(:seating_chart)).to be_present
  end

  it "registers all four image-bearing models" do
    Rails.application.eager_load!
    expect(Describable.registry.values).to include(Building, Floor, Room, MediaAsset)
  end
end
