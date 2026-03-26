require "rails_helper"

RSpec.describe "Project Memberships", type: :request do
  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }
  let!(:ws_membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let(:project) { create(:project, workspace: workspace, created_by: user) }
  let!(:creator_pm) { create(:project_membership, :creator, project: project, user: user) }

  before do
    Current.workspace = workspace
    sign_in(user)
  end

  describe "GET memberships index" do
    it "lists project members" do
      get workspace_project_memberships_path(workspace, project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.full_name)
    end
  end

  describe "POST create membership" do
    let(:new_member) { create(:user) }
    let!(:new_ws_membership) { create(:membership, user: new_member, workspace: workspace) }

    it "adds a workspace member as editor" do
      expect {
        post workspace_project_memberships_path(workspace, project), params: {
          project_membership: { user_id: new_member.id, role: "editor" }
        }
      }.to change(ProjectMembership, :count).by(1)
    end

    it "rejects non-workspace members" do
      outsider = create(:user)
      post workspace_project_memberships_path(workspace, project), params: {
        project_membership: { user_id: outsider.id, role: "editor" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH update membership role" do
    let(:member_user) { create(:user) }
    let!(:member_ws) { create(:membership, user: member_user, workspace: workspace) }
    let!(:member_pm) { create(:project_membership, project: project, user: member_user) }

    it "changes the member's role" do
      patch workspace_project_membership_path(workspace, project, member_pm), params: {
        project_membership: { role: "viewer" }
      }
      expect(member_pm.reload).to be_viewer
    end
  end

  describe "DELETE membership" do
    let(:member_user) { create(:user) }
    let!(:member_ws) { create(:membership, user: member_user, workspace: workspace) }
    let!(:member_pm) { create(:project_membership, project: project, user: member_user) }

    it "removes the member" do
      expect {
        delete workspace_project_membership_path(workspace, project, member_pm)
      }.to change(ProjectMembership, :count).by(-1)
    end

    it "prevents removing the creator" do
      delete workspace_project_membership_path(workspace, project, creator_pm)
      expect(response).to have_http_status(:redirect)
      expect(creator_pm.reload).to be_persisted
    end
  end

  describe "PATCH toggle_pin" do
    it "pins own membership" do
      patch toggle_pin_workspace_project_membership_path(workspace, project, creator_pm)
      expect(creator_pm.reload).to be_pinned
    end

    it "unpins a pinned membership" do
      creator_pm.update!(pinned: true)
      patch toggle_pin_workspace_project_membership_path(workspace, project, creator_pm)
      expect(creator_pm.reload).not_to be_pinned
    end
  end
end
