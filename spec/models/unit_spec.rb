require "rails_helper"

RSpec.describe Unit, type: :model do
  let(:record) { create(:unit) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires department_group" do
      unit = build(:unit, department_group: nil)
      expect(unit).not_to be_valid
    end

    it "enforces department_group uniqueness within a workspace" do
      workspace = create(:workspace)
      create(:unit, workspace: workspace, department_group: "DEPT_GROUP_1")
      duplicate = build(:unit, workspace: workspace, department_group: "DEPT_GROUP_1")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:department_group]).not_to be_empty
    end

    it "allows the same department_group in a different workspace" do
      create(:unit, department_group: "DEPT_GROUP_1")
      other = build(:unit, department_group: "DEPT_GROUP_1")

      expect(other).to be_valid
    end
  end

  describe "#display_name" do
    it "returns the UnitDisplayName override when one exists for the department_group" do
      unit = create(:unit, workspace: record.workspace, department_group: "DEPT_GROUP_OVERRIDE", description: "Raw description")
      create(:unit_display_name, workspace: unit.workspace, department_group: "DEPT_GROUP_OVERRIDE", display_name: "Nice Name")

      expect(unit.display_name).to eq("Nice Name")
    end

    it "returns description when no override exists" do
      unit = create(:unit, department_group: "DEPT_GROUP_NO_OVERRIDE", description: "Raw description")

      expect(unit.display_name).to eq("Raw description")
    end

    it "returns department_group when no override and no description" do
      unit = create(:unit, department_group: "DEPT_GROUP_BARE", description: nil)

      expect(unit.display_name).to eq("DEPT_GROUP_BARE")
    end

    it "does not apply a UnitDisplayName override from another workspace" do
      unit = create(:unit, department_group: "DEPT_GROUP_OTHER", description: "Raw description")
      create(:unit_display_name, department_group: "DEPT_GROUP_OTHER", display_name: "Wrong Workspace Name")

      expect(unit.display_name).to eq("Raw description")
    end
  end
end
