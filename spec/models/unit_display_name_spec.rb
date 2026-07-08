require "rails_helper"

RSpec.describe UnitDisplayName, type: :model do
  let(:record) { create(:unit_display_name) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires department_group" do
      unit_display_name = build(:unit_display_name, department_group: nil)
      expect(unit_display_name).not_to be_valid
    end

    it "requires display_name" do
      unit_display_name = build(:unit_display_name, display_name: nil)
      expect(unit_display_name).not_to be_valid
    end

    it "enforces department_group uniqueness within a workspace" do
      workspace = create(:workspace)
      create(:unit_display_name, workspace: workspace, department_group: "LSA-PSYCH")
      duplicate = build(:unit_display_name, workspace: workspace, department_group: "LSA-PSYCH")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:department_group]).not_to be_empty
    end

    it "allows the same department_group in a different workspace" do
      create(:unit_display_name, department_group: "LSA-PSYCH")
      other = build(:unit_display_name, department_group: "LSA-PSYCH")

      expect(other).to be_valid
    end
  end
end
