require "rails_helper"

RSpec.describe Floor, type: :model do
  let(:record) { create(:floor) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires a label" do
      floor = build(:floor, label: nil)
      expect(floor).not_to be_valid
    end

    it "is invalid with a duplicate label within the same building" do
      building = create(:building)
      create(:floor, building: building, label: "1")
      duplicate = build(:floor, building: building, label: "1")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:label]).not_to be_empty
    end

    it "allows the same label in a different building" do
      create(:floor, label: "1")
      other = build(:floor, label: "1")

      expect(other).to be_valid
    end
  end

  describe "plan attachment validations" do
    it "accepts a PDF (allowed for floor plans)" do
      floor = build(:floor)
      floor.plan.attach(
        io: StringIO.new("fake pdf content"),
        filename: "plan.pdf",
        content_type: "application/pdf"
      )
      expect(floor).to be_valid
    end

    it "rejects a GIF" do
      floor = build(:floor)
      floor.plan.attach(
        io: StringIO.new("fake gif content"),
        filename: "plan.gif",
        content_type: "image/gif"
      )
      expect(floor).not_to be_valid
      expect(floor.errors[:plan]).not_to be_empty
    end
  end
end
