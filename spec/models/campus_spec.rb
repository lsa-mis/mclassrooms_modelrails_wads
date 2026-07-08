require "rails_helper"

RSpec.describe Campus, type: :model do
  let(:record) { create(:campus) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires code" do
      campus = build(:campus, code: nil)
      expect(campus).not_to be_valid
    end

    it "enforces code uniqueness within a workspace" do
      workspace = create(:workspace)
      create(:campus, workspace: workspace, code: "101")
      duplicate = build(:campus, workspace: workspace, code: "101")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:code]).not_to be_empty
    end

    it "allows the same code in a different workspace" do
      create(:campus, code: "101")
      other = build(:campus, code: "101")

      expect(other).to be_valid
    end
  end
end
