require "rails_helper"

RSpec.describe Workspaces::BrandingPolicy do
  let(:workspace) { create(:workspace) }

  before { Current.workspace = workspace }

  describe "for owner" do
    let(:user) { create(:user) }
    before { create(:membership, :owner, user: user, workspace: workspace) }

    it "allows edit" do
      expect(described_class.new(user, workspace).edit?).to be true
    end

    it "allows update" do
      expect(described_class.new(user, workspace).update?).to be true
    end

    it "allows destroy" do
      expect(described_class.new(user, workspace).destroy?).to be true
    end
  end

  describe "for member" do
    let(:user) { create(:user) }
    before { create(:membership, user: user, workspace: workspace) }

    it "denies edit" do
      expect(described_class.new(user, workspace).edit?).to be false
    end

    it "denies update" do
      expect(described_class.new(user, workspace).update?).to be false
    end

    it "denies destroy" do
      expect(described_class.new(user, workspace).destroy?).to be false
    end
  end
end
