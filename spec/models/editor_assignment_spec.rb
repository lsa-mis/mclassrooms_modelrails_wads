require "rails_helper"

RSpec.describe EditorAssignment, type: :model do
  let(:record) { create(:editor_assignment) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires a user" do
      assignment = build(:editor_assignment, user: nil)
      expect(assignment).not_to be_valid
    end

    it "requires a unit" do
      assignment = build(:editor_assignment, unit: nil, workspace: create(:workspace))
      expect(assignment).not_to be_valid
    end

    it "is invalid with a duplicate (user, unit) pair" do
      user = create(:user)
      unit = create(:unit)
      create(:editor_assignment, user: user, unit: unit)
      duplicate = build(:editor_assignment, user: user, unit: unit)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).not_to be_empty
    end

    it "allows the same user on a different unit" do
      user = create(:user)
      create(:editor_assignment, user: user)
      other = build(:editor_assignment, user: user)

      expect(other).to be_valid
    end

    it "allows the same unit on a different user" do
      unit = create(:unit)
      create(:editor_assignment, unit: unit)
      other = build(:editor_assignment, unit: unit)

      expect(other).to be_valid
    end

    it "allows the same user to be assigned to different units" do
      # The uniqueness scope is :unit_id, so a user editing multiple units is
      # valid — only the exact (user, unit) pair is rejected. (A pair cannot
      # span workspaces: a Unit belongs to exactly one workspace.)
      user = create(:user)
      workspace = create(:workspace)
      unit = create(:unit, workspace: workspace)
      other_unit = create(:unit, workspace: workspace)
      create(:editor_assignment, user: user, unit: unit, workspace: workspace)

      other = build(:editor_assignment, user: user, unit: other_unit, workspace: workspace)

      expect(other).to be_valid
    end
  end

  describe "schema" do
    it "has a unique composite index on [user_id, unit_id]" do
      indexes = ActiveRecord::Base.connection.indexes("editor_assignments")
      index = indexes.find { |i| i.columns == [ "user_id", "unit_id" ] }
      expect(index).to be_present, "Expected unique composite index on (user_id, unit_id)"
      expect(index.unique).to be true
    end
  end
end
