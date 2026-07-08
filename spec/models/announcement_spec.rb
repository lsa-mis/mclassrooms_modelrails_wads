require "rails_helper"

RSpec.describe Announcement, type: :model do
  let(:record) { create(:announcement) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires a slot" do
      announcement = build(:announcement, slot: nil)
      expect(announcement).not_to be_valid
    end

    it "requires a body" do
      announcement = build(:announcement, body: nil)
      expect(announcement).not_to be_valid
    end

    it "is invalid with a duplicate slot" do
      create(:announcement, slot: "home_page")
      duplicate = build(:announcement, slot: "home_page", workspace: create(:workspace))

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slot]).not_to be_empty
    end

    it "enforces uniqueness at the database level" do
      create(:announcement, slot: "home_page")
      duplicate = build(:announcement, slot: "home_page", workspace: create(:workspace))

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "enum slot" do
    it "supports the three defined slots" do
      expect(Announcement.slots.keys).to contain_exactly(
        "home_page", "find_a_room_page", "about_page"
      )
    end
  end

  describe "rich text body" do
    it "supports has_rich_text body" do
      announcement = create(:announcement, body: "Welcome!")
      expect(announcement.body.to_plain_text).to eq("Welcome!")
    end
  end

  describe ".for" do
    it "returns the announcement for a set slot" do
      announcement = create(:announcement, slot: "home_page")
      expect(Announcement.for(:home_page)).to eq(announcement)
    end

    it "returns nil for an unset slot" do
      expect(Announcement.for(:about_page)).to be_nil
    end
  end
end
