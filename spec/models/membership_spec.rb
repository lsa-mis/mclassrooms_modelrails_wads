require "rails_helper"

RSpec.describe Membership, type: :model do
  describe "validations" do
    it "requires a user" do
      membership = build(:membership, user: nil)
      expect(membership).not_to be_valid
    end

    it "requires a workspace" do
      membership = build(:membership, workspace: nil)
      expect(membership).not_to be_valid
    end

    it "requires a role" do
      membership = build(:membership, role: nil)
      expect(membership).not_to be_valid
    end

    it "enforces one membership per user per workspace" do
      membership = create(:membership)
      duplicate = build(:membership, user: membership.user, workspace: membership.workspace)
      expect(duplicate).not_to be_valid
    end
  end

  describe "Discardable" do
    let(:membership) { create(:membership) }

    it "can be discarded" do
      membership.discard!
      expect(membership).to be_discarded
    end
  end

  describe "associations" do
    it "belongs to user" do
      expect(Membership.reflect_on_association(:user).macro).to eq(:belongs_to)
    end

    it "belongs to workspace" do
      expect(Membership.reflect_on_association(:workspace).macro).to eq(:belongs_to)
    end

    it "belongs to role" do
      expect(Membership.reflect_on_association(:role).macro).to eq(:belongs_to)
    end
  end
end
