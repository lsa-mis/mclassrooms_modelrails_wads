require "rails_helper"

RSpec.describe "Workspace Members", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  describe "GET /workspaces/:workspace_slug/members" do
    it "lists workspace members" do
      get workspace_members_path(workspace)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.full_name)
    end

    it "shows member roles" do
      get workspace_members_path(workspace)
      expect(response.body).to include("Owner")
    end
  end

  describe "GET /workspaces/:workspace_slug/members/:id/edit" do
    let(:target) { create(:user) }
    let!(:target_membership) { create(:membership, user: target, workspace: workspace) }

    it "renders the role change form" do
      get edit_workspace_member_path(workspace, target_membership)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /workspaces/:workspace_slug/members/:id" do
    let(:target) { create(:user) }
    let!(:target_membership) { create(:membership, user: target, workspace: workspace) }
    let(:admin_role) { Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" } }

    it "changes the member's role" do
      patch workspace_member_path(workspace, target_membership), params: { membership: { role_id: admin_role.id } }
      expect(target_membership.reload.role).to eq(admin_role)
    end

    it "redirects to members list" do
      patch workspace_member_path(workspace, target_membership), params: { membership: { role_id: admin_role.id } }
      expect(response).to redirect_to(workspace_members_path(workspace))
    end
  end

  describe "DELETE /workspaces/:workspace_slug/members/:id" do
    let(:target) { create(:user) }
    let!(:target_membership) { create(:membership, user: target, workspace: workspace) }

    it "deactivates the member" do
      delete workspace_member_path(workspace, target_membership)
      expect(target_membership.reload).to be_discarded
    end

    it "redirects to members list" do
      delete workspace_member_path(workspace, target_membership)
      expect(response).to redirect_to(workspace_members_path(workspace))
    end
  end

  describe "PATCH /workspaces/:workspace_slug/members/:id/reactivate" do
    let(:target) { create(:user) }
    let!(:target_membership) { create(:membership, user: target, workspace: workspace) }

    before { target_membership.discard! }

    it "reactivates the member" do
      patch reactivate_workspace_member_path(workspace, target_membership)
      expect(target_membership.reload).not_to be_discarded
    end
  end

  describe "PATCH /workspaces/:workspace_slug/members/:id/transfer_ownership" do
    let(:target) { create(:user) }
    let!(:target_membership) { create(:membership, user: target, workspace: workspace) }

    it "transfers ownership" do
      owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
      admin_role = Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" }
      patch transfer_ownership_workspace_member_path(workspace, target_membership)
      expect(target_membership.reload.role).to eq(owner_role)
      expect(membership.reload.role).to eq(admin_role)
    end
  end

  describe "member authorization" do
    let(:member_user) { create(:user) }
    before { create(:membership, user: member_user, workspace: workspace) }

    it "denies role change for regular members" do
      target = create(:membership, workspace: workspace)
      sign_in(member_user)
      patch workspace_member_path(workspace, target), params: { membership: { role_id: membership.role_id } }
      expect(response).to have_http_status(:redirect)
    end
  end
end
