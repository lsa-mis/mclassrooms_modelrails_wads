require "rails_helper"

RSpec.describe RoomGalleryImage, type: :model do
  let(:record) { create(:room_gallery_image) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires a room" do
      image = build(:room_gallery_image, room: nil, workspace: create(:workspace))
      expect(image).not_to be_valid
    end

    it "requires position to be non-negative" do
      image = build(:room_gallery_image, position: -1)
      expect(image).not_to be_valid
      expect(image.errors[:position]).not_to be_empty
    end

    it "allows a zero position" do
      image = build(:room_gallery_image, position: 0)
      expect(image).to be_valid
    end

    it "does not cap the number of gallery images per room in the schema (D9 — UI enforces 5 in phase 4)" do
      room = create(:room)
      6.times { |n| create(:room_gallery_image, room: room, position: n) }
      expect(room.gallery_images.count).to eq(6)
    end
  end

  describe "image attachment validations" do
    it "accepts a small PNG" do
      image = build(:room_gallery_image)
      image.image.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "gallery.png",
        content_type: "image/png"
      )
      expect(image).to be_valid
    end

    it "is invalid without an attached image" do
      image = build(:room_gallery_image)
      image.image.detach
      expect(image).not_to be_valid
      expect(image.errors[:image]).not_to be_empty
    end

    it "rejects a PDF" do
      image = build(:room_gallery_image)
      image.image.attach(
        io: StringIO.new("fake pdf content"),
        filename: "gallery.pdf",
        content_type: "application/pdf"
      )
      expect(image).not_to be_valid
      expect(image.errors[:image]).not_to be_empty
    end

    it "rejects an oversized (11MB) PNG" do
      image = build(:room_gallery_image)
      image.image.attach(
        io: StringIO.new("x" * 11.megabytes),
        filename: "gallery.png",
        content_type: "image/png"
      )
      expect(image).not_to be_valid
      expect(image.errors[:image]).not_to be_empty
    end
  end

  describe ".ordered" do
    it "sorts by position ascending, with id as a tiebreak" do
      room = create(:room)
      third = create(:room_gallery_image, room: room, position: 2)
      first_a = create(:room_gallery_image, room: room, position: 0)
      first_b = create(:room_gallery_image, room: room, position: 0)
      second = create(:room_gallery_image, room: room, position: 1)

      expect(room.gallery_images.ordered).to eq([ first_a, first_b, second, third ])
    end
  end
end
