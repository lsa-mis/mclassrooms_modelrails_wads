require "rails_helper"

RSpec.describe "Turbo Stream broadcasts" do
  describe "workspace-level broadcasts" do
    let(:workspace) { create(:workspace) }

    it "Workspace broadcasts refresh on update" do
      expect(workspace).to receive(:broadcast_refresh_to).with(workspace)
      workspace.update!(name: "Updated Name")
    end

    it "Membership broadcasts refresh on create" do
      user = create(:user)
      membership = build(:membership, user: user, workspace: workspace)
      expect(membership).to receive(:broadcast_refresh_to).with(workspace)
      membership.save!
    end

    it "Invitation broadcasts refresh on update" do
      invitation = create(:invitation, invitable: workspace)
      expect(invitation).to receive(:broadcast_refresh_to).with(workspace)
      invitation.decline!
    end

    it "Project broadcasts refresh to workspace on create" do
      user = create(:user)
      create(:membership, user: user, workspace: workspace)
      project = workspace.projects.build(name: "New", created_by: user)
      expect(project).to receive(:broadcast_refresh_to).with(workspace)
      project.save!
    end
  end

  describe "project-level broadcasts" do
    let(:workspace) { create(:workspace) }
    let(:user) { create(:user) }
    let(:project) { create(:project, workspace: workspace, created_by: user) }
    before { create(:membership, user: user, workspace: workspace) }

    it "Resource broadcasts refresh to project on create" do
      doc = Document.create!
      resource = project.resources.build(title: "Test", resourceable: doc, created_by: user)
      expect(resource).to receive(:broadcast_refresh_to).with(project)
      resource.save!
    end

    it "ProjectMembership broadcasts refresh to project on create" do
      new_member = create(:user)
      create(:membership, user: new_member, workspace: workspace)
      pm = project.project_memberships.build(user: new_member, role: "editor")
      expect(pm).to receive(:broadcast_refresh_to).with(project)
      pm.save!
    end
  end

  describe "broadcast resilience" do
    it "does not break on broadcast failure" do
      workspace = create(:workspace)
      allow(workspace).to receive(:broadcast_refresh_to).and_raise(StandardError, "Redis down")
      expect { workspace.update!(name: "Still works") }.not_to raise_error
      expect(workspace.reload.name).to eq("Still works")
    end
  end
end
