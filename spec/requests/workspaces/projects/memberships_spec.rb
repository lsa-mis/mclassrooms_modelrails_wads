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

  describe "PATCH with invalid role" do
    let(:member_user) { create(:user) }
    let!(:member_ws) { create(:membership, user: member_user, workspace: workspace) }
    let!(:member_pm) { create(:project_membership, project: project, user: member_user) }

    it "handles invalid role gracefully" do
      patch workspace_project_membership_path(workspace, project, member_pm), params: {
        project_membership: { role: "superadmin" }
      }
      expect(response).to redirect_to(workspace_project_memberships_path(workspace, project))
    end
  end

  describe "authorization" do
    let(:editor_user) { create(:user) }
    let!(:editor_ws) { create(:membership, user: editor_user, workspace: workspace) }
    let!(:editor_pm) { create(:project_membership, project: project, user: editor_user) }
    let(:target_user) { create(:user) }
    let!(:target_ws) { create(:membership, user: target_user, workspace: workspace) }

    describe "editor cannot add members" do
      before { sign_in(editor_user) }

      it "denies creating a membership" do
        expect {
          post workspace_project_memberships_path(workspace, project), params: {
            project_membership: { user_id: target_user.id, role: "viewer" }
          }
        }.not_to change(ProjectMembership, :count)
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "editor cannot change roles" do
      let!(:target_pm) { create(:project_membership, :viewer, project: project, user: target_user) }
      before { sign_in(editor_user) }

      it "denies updating a membership role" do
        patch workspace_project_membership_path(workspace, project, target_pm), params: {
          project_membership: { role: "editor" }
        }
        expect(target_pm.reload).to be_viewer
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "editor cannot remove members" do
      let!(:target_pm) { create(:project_membership, :viewer, project: project, user: target_user) }
      before { sign_in(editor_user) }

      it "denies deleting a membership" do
        expect {
          delete workspace_project_membership_path(workspace, project, target_pm)
        }.not_to change(ProjectMembership, :count)
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "viewer cannot add members" do
      let(:viewer_user) { create(:user) }
      let!(:viewer_ws) { create(:membership, user: viewer_user, workspace: workspace) }
      let!(:viewer_pm) { create(:project_membership, :viewer, project: project, user: viewer_user) }
      before { sign_in(viewer_user) }

      it "denies creating a membership" do
        expect {
          post workspace_project_memberships_path(workspace, project), params: {
            project_membership: { user_id: target_user.id, role: "editor" }
          }
        }.not_to change(ProjectMembership, :count)
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "non-project-member cannot access memberships" do
      let(:outsider) { create(:user) }
      let!(:outsider_ws) { create(:membership, user: outsider, workspace: workspace) }
      before { sign_in(outsider) }

      it "denies listing memberships" do
        get workspace_project_memberships_path(workspace, project)
        expect(response).to have_http_status(:redirect)
      end

      it "denies adding a member with arbitrary user_id" do
        expect {
          post workspace_project_memberships_path(workspace, project), params: {
            project_membership: { user_id: target_user.id, role: "editor" }
          }
        }.not_to change(ProjectMembership, :count)
        expect(response).to have_http_status(:redirect)
      end
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
