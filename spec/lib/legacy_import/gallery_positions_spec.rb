require "rails_helper"

RSpec.describe LegacyImport::GalleryPositions do
  def entry(slot, filename) = { "attachment_name" => slot, "filename" => filename }

  def placements(*entries) = described_class.call(entries).map { |p| [ p.entry["attachment_name"], p.position, p.source ] }

  it "puts room_image first and gallery_imageN at N + 1 when filenames say nothing" do
    expect(placements(entry("room_image", "front.jpg"), entry("gallery_image1", "b.jpg"), entry("gallery_image5", "x.jpg")))
      .to eq([ [ "room_image", 1, :slot ], [ "gallery_image1", 2, :slot ], [ "gallery_image5", 6, :slot ] ])
  end

  it "prefers Grace's Image N from the filename" do
    expect(placements(entry("room_image", "BSB 1060 Image 1 2026.jpeg"), entry("gallery_image2", "BSB 1060 Image 5 2026.jpeg")))
      .to eq([ [ "room_image", 1, :slot ], [ "gallery_image2", 5, :filename ] ])
  end

  it "falls back to slots for the whole room when two files claim the same shot" do
    expect(placements(entry("room_image", "front.jpg"), entry("gallery_image1", "A Image 1.jpg")))
      .to eq([ [ "room_image", 1, :slot ], [ "gallery_image1", 2, :slot ] ])
  end

  it "keeps room_image at 1 whatever its filename says" do
    expect(placements(entry("room_image", "A Image 3.jpg"), entry("gallery_image1", "A Image 2.jpg")))
      .to eq([ [ "room_image", 1, :slot ], [ "gallery_image1", 2, :filename ] ])
  end

  it "ignores an Image 0" do
    expect(placements(entry("gallery_image3", "A Image 0.jpg"))).to eq([ [ "gallery_image3", 4, :slot ] ])
  end
end
