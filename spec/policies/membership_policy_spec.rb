require "rails_helper"

RSpec.describe MembershipPolicy do
  let(:workspace) { create(:workspace) }

  before { Current.workspace = workspace }

  describe "for owner" do
    let(:user) { create(:user) }
    let(:other_membership) { create(:membership, workspace: workspace) }
    before { create(:membership, :owner, user: user, workspace: workspace) }

    it "allows index" do
      expect(described_class.new(user, other_membership).index?).to be true
    end

    it "allows update" do
      expect(described_class.new(user, other_membership).update?).to be true
    end

    it "allows destroy" do
      expect(described_class.new(user, other_membership).destroy?).to be true
    end

    it "denies destroying self" do
      own_membership = workspace.memberships.kept.find_by(user: user)
      expect(described_class.new(user, own_membership).destroy?).to be false
    end

    it "allows reactivate" do
      expect(described_class.new(user, other_membership).reactivate?).to be true
    end

    it "allows transfer_ownership" do
      expect(described_class.new(user, other_membership).transfer_ownership?).to be true
    end
  end

  describe "for member" do
    let(:user) { create(:user) }
    let(:other_membership) { create(:membership, workspace: workspace) }
    before { create(:membership, user: user, workspace: workspace) }

    it "allows index" do
      expect(described_class.new(user, other_membership).index?).to be true
    end

    it "denies update" do
      expect(described_class.new(user, other_membership).update?).to be false
    end

    it "denies destroy" do
      expect(described_class.new(user, other_membership).destroy?).to be false
    end

    it "denies transfer_ownership" do
      expect(described_class.new(user, other_membership).transfer_ownership?).to be false
    end
  end
end
