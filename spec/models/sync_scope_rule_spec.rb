require "rails_helper"

RSpec.describe SyncScopeRule, type: :model do
  let(:record) { create(:sync_scope_rule) }

  it_behaves_like "a tenanted directory record"

  describe "validations" do
    it "requires value" do
      rule = build(:sync_scope_rule, value: nil)
      expect(rule).not_to be_valid
    end

    it "enforces [rule_type, value] uniqueness within a workspace" do
      workspace = create(:workspace)
      create(:sync_scope_rule, workspace: workspace, rule_type: "campus_allow", value: "AA")
      duplicate = build(:sync_scope_rule, workspace: workspace, rule_type: "campus_allow", value: "AA")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:value]).not_to be_empty
    end

    it "allows the same value under a different rule_type in the same workspace" do
      workspace = create(:workspace)
      create(:sync_scope_rule, workspace: workspace, rule_type: "campus_allow", value: "AA")
      other = build(:sync_scope_rule, workspace: workspace, rule_type: "building_allow", value: "AA")

      expect(other).to be_valid
    end

    it "allows the same [rule_type, value] in a different workspace" do
      create(:sync_scope_rule, rule_type: "campus_allow", value: "AA")
      other = build(:sync_scope_rule, rule_type: "campus_allow", value: "AA")

      expect(other).to be_valid
    end
  end

  describe "rule_type enum" do
    it "supports campus_allow" do
      rule = build(:sync_scope_rule, rule_type: "campus_allow")
      expect(rule.campus_allow?).to be true
    end

    it "supports building_allow" do
      rule = build(:sync_scope_rule, rule_type: "building_allow")
      expect(rule.building_allow?).to be true
    end

    it "supports building_exclude" do
      rule = build(:sync_scope_rule, rule_type: "building_exclude")
      expect(rule.building_exclude?).to be true
    end

    it "raises ArgumentError for an unknown rule_type" do
      rule = build(:sync_scope_rule)
      expect { rule.rule_type = "bogus_type" }.to raise_error(ArgumentError)
    end
  end
end
