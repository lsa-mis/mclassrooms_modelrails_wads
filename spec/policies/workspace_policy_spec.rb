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

    it "allows archive and unarchive" do
      expect(described_class.new(user, workspace).archive?).to be true
      expect(described_class.new(user, workspace).unarchive?).to be true
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

    it "denies archive and unarchive" do
      expect(described_class.new(user, workspace).archive?).to be false
      expect(described_class.new(user, workspace).unarchive?).to be false
    end
  end

  describe "for any authenticated user" do
    let(:user) { create(:user) }

    it "allows index" do
      expect(described_class.new(user, Workspace).index?).to be true
    end

    it "allows create" do
      expect(described_class.new(user, Workspace).create?).to be true
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

  describe "home-workspace exemption" do
    let(:user) { create(:user) }
    let(:home) { create(:workspace, personal: true) }

    before do
      Current.workspace = home
      create(:membership, :owner, user: user, workspace: home)
    end

    it "denies archive/unarchive/destroy on a personal (home) workspace even for an owner" do
      policy = described_class.new(user, home)
      expect(policy.archive?).to be false
      expect(policy.unarchive?).to be false
      expect(policy.destroy?).to be false
    end
  end

  # Fork divergence (MiClassrooms, 2026-07-17): under the SHARED (directory)
  # posture the workspace dashboard is admin-only — only directory admins
  # (owner/admin slugs) may show? it. Every other posture (including the default
  # test env exercised above) keeps the member-visible dashboard. See
  # WorkspacePolicy#show? and ApplicationController#not_authorized_redirect_path.
  describe "show? under the shared (directory) posture" do
    before { allow(TenancyConfig).to receive(:shared?).and_return(true) }

    let(:owner)  { create(:user).tap { |u| create(:membership, :owner, user: u, workspace: workspace) } }
    let(:admin)  { create(:user).tap { |u| create(:membership, user: u, workspace: workspace, role: Role.system_default!("admin")) } }
    let(:member) { create(:user).tap { |u| create(:membership, user: u, workspace: workspace) } }
    let(:viewer) { create(:user).tap { |u| create(:membership, user: u, workspace: workspace, role: Role.system_default!("viewer")) } }

    it "allows directory admins (owner, admin) to view the dashboard" do
      expect(described_class.new(owner, workspace).show?).to be true
      expect(described_class.new(admin, workspace).show?).to be true
    end

    it "denies non-admin members and viewers (the dashboard is an admin surface)" do
      expect(described_class.new(member, workspace).show?).to be false
      expect(described_class.new(viewer, workspace).show?).to be false
    end
  end
end
