require "rails_helper"

RSpec.describe ProjectMembership, type: :model do
  describe "validations" do
    it "requires a project" do
      pm = build(:project_membership, project: nil)
      expect(pm).not_to be_valid
    end

    it "requires a user" do
      pm = build(:project_membership, user: nil)
      expect(pm).not_to be_valid
    end

    it "enforces one membership per user per project" do
      pm = create(:project_membership)
      duplicate = build(:project_membership, project: pm.project, user: pm.user)
      expect(duplicate).not_to be_valid
    end

    it "validates user is a workspace member" do
      project = create(:project)
      outsider = create(:user)
      pm = build(:project_membership, project: project, user: outsider)
      pm.valid?
      expect(pm.errors[:user]).to be_present
    end

    it "allows workspace members" do
      workspace = create(:workspace)
      user = create(:user)
      create(:membership, user: user, workspace: workspace)
      project = create(:project, workspace: workspace, created_by: user)
      pm = build(:project_membership, project: project, user: user)
      expect(pm).to be_valid
    end
  end

  describe "role enum" do
    it "defaults to editor" do
      pm = ProjectMembership.new
      expect(pm.role).to eq("editor")
    end

    it "supports creator" do
      pm = build(:project_membership, :creator)
      expect(pm).to be_creator
    end

    it "supports viewer" do
      pm = build(:project_membership, :viewer)
      expect(pm).to be_viewer
    end
  end

  describe "scopes" do
    it "returns pinned memberships" do
      pinned = create(:project_membership, :pinned)
      unpinned = create(:project_membership)
      expect(ProjectMembership.pinned).to contain_exactly(pinned)
    end
  end

  describe "cascade on workspace membership discard" do
    it "destroys project memberships when workspace membership is deactivated" do
      workspace = create(:workspace)
      user = create(:user)
      other_owner = create(:user)
      create(:membership, :owner, user: user, workspace: workspace)
      create(:membership, :owner, user: other_owner, workspace: workspace)
      project = create(:project, workspace: workspace, created_by: user)
      create(:project_membership, :creator, project: project, user: user)

      workspace_membership = workspace.memberships.find_by(user: user)
      workspace_membership.deactivate!

      expect(ProjectMembership.where(user: user, project: project)).to be_empty
    end
  end
end
