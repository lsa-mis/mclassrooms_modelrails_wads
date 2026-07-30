require "rails_helper"

RSpec.describe Describable do
  # RoomGalleryImage is the first real consumer (slot :image).
  subject(:record) { build(:room_gallery_image, image_alt: nil, image_derived_ok: false) }

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
    RoomGalleryImage
    expect(Describable.registry.values).to include(RoomGalleryImage)
  end
end
