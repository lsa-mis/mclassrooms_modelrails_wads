require "rails_helper"

RSpec.describe WorkspaceJoinLinkPolicy do
  let(:workspace) { create(:workspace) }

  before { Current.workspace = workspace }

  # The controller authorizes the class (`authorize WorkspaceJoinLink`), so the
  # record here is the class — permission derives from the user's membership in
  # Current.workspace, not from the record. Every action gates on
  # `manage_settings`, so index is admin-only here (unlike InvitationPolicy,
  # whose index is a read gate).
  let(:record) { WorkspaceJoinLink }

  describe "for an owner" do
    let(:user) { create(:user) }
    before { create(:membership, :owner, user: user, workspace: workspace) }

    it "allows index" do
      expect(described_class.new(user, record).index?).to be true
    end

    it "allows create" do
      expect(described_class.new(user, record).create?).to be true
    end

    it "allows destroy" do
      expect(described_class.new(user, record).destroy?).to be true
    end
  end

  describe "for a member" do
    let(:user) { create(:user) }
    before { create(:membership, user: user, workspace: workspace) }

    it "denies index" do
      expect(described_class.new(user, record).index?).to be false
    end

    it "denies create" do
      expect(described_class.new(user, record).create?).to be false
    end

    it "denies destroy" do
      expect(described_class.new(user, record).destroy?).to be false
    end
  end

  describe "for a viewer" do
    let(:user) { create(:user) }
    let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }
    before { create(:membership, user: user, workspace: workspace, role: viewer_role) }

    it "denies index" do
      expect(described_class.new(user, record).index?).to be false
    end

    it "denies create" do
      expect(described_class.new(user, record).create?).to be false
    end

    it "denies destroy" do
      expect(described_class.new(user, record).destroy?).to be false
    end
  end
end
