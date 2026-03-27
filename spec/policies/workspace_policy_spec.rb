require "rails_helper"

RSpec.describe WorkspacePolicy do
  let(:workspace) { create(:workspace) }

  before { Current.workspace = workspace }

  describe "for owner" do
    let(:user) { create(:user) }
    before { create(:membership, :owner, user: user, workspace: workspace) }

    it "allows show" do
      expect(described_class.new(user, workspace).show?).to be true
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

    it "allows show" do
      expect(described_class.new(user, workspace).show?).to be true
    end

    it "denies update" do
      expect(described_class.new(user, workspace).update?).to be false
    end

    it "denies destroy" do
      expect(described_class.new(user, workspace).destroy?).to be false
    end
  end

  describe "for viewer" do
    let(:user) { create(:user) }
    let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }
    before { create(:membership, user: user, workspace: workspace, role: viewer_role) }

    it "allows show" do
      expect(described_class.new(user, workspace).show?).to be true
    end

    it "denies update" do
      expect(described_class.new(user, workspace).update?).to be false
    end

    it "denies destroy" do
      expect(described_class.new(user, workspace).destroy?).to be false
    end
  end
end
