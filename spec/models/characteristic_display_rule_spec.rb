require "rails_helper"

RSpec.describe CharacteristicDisplayRule, type: :model do
  let(:record) { create(:characteristic_display_rule) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires short_code" do
      rule = build(:characteristic_display_rule, short_code: nil)
      expect(rule).not_to be_valid
    end

    it "enforces short_code uniqueness within a workspace" do
      workspace = create(:workspace)
      create(:characteristic_display_rule, workspace: workspace, short_code: "WIFI")
      duplicate = build(:characteristic_display_rule, workspace: workspace, short_code: "WIFI")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:short_code]).not_to be_empty
    end

    it "allows the same short_code in a different workspace" do
      create(:characteristic_display_rule, short_code: "WIFI")
      other = build(:characteristic_display_rule, short_code: "WIFI")

      expect(other).to be_valid
    end
  end

  describe "defaults" do
    it "defaults filterable to true" do
      rule = CharacteristicDisplayRule.new(workspace: create(:workspace), short_code: "WIFI")
      expect(rule.filterable).to be true
    end

    it "defaults team_learning to false" do
      rule = CharacteristicDisplayRule.new(workspace: create(:workspace), short_code: "WIFI")
      expect(rule.team_learning).to be false
    end
  end
end
