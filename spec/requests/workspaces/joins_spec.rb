require "rails_helper"

RSpec.describe "Workspaces::Joins (Flow A: authenticated user joins via link)", type: :request do
  let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
  let(:owner)     { create(:user) }
  let(:newcomer)  { create(:user) }
  let!(:owner_role) {
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    }
  }
  let!(:member_role) {
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
      r.name = "Member"
      r.permissions = { manage_projects: true }
    }
  }
  let(:link) { create(:workspace_join_link, workspace: workspace, created_by: owner) }

  before do
    allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    workspace.memberships.create!(user: owner, role: owner_role)
    sign_in(newcomer)
  end

  describe "POST /workspaces/:slug/joins/:token" do
    it "admits the user as a Member and redirects to the workspace" do
      expect {
        post workspace_join_path(workspace, token: link.token)
      }.to change(workspace.memberships, :count).by(1)

      membership = workspace.memberships.find_by!(user: newcomer)
      expect(membership.role).to eq(member_role)
      expect(response).to redirect_to(workspace_path(workspace))
    end

    it "rejects a revoked link" do
      link.revoke!
      expect {
        post workspace_join_path(workspace, token: link.token)
      }.not_to change(workspace.memberships, :count)
      expect(response).to redirect_to(root_path)
    end

    it "rejects when the workspace's join_policy is not open_link" do
      workspace.update!(join_policy: "invite")
      expect {
        post workspace_join_path(workspace, token: link.token)
      }.not_to change(workspace.memberships, :count)
      expect(response).to redirect_to(root_path)
    end

    it "rejects when the instance allowlist excludes :open_link" do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite])
      expect {
        post workspace_join_path(workspace, token: link.token)
      }.not_to change(workspace.memberships, :count)
      expect(response).to redirect_to(root_path)
    end

    it "surfaces a clean message when the workspace is at capacity" do
      workspace.update!(max_members: 1)  # owner already fills capacity
      post workspace_join_path(workspace, token: link.token)
      expect(workspace.memberships.find_by(user: newcomer)).to be_nil
      expect(flash[:alert]).to be_present
    end

    it "redirects gracefully when the user is already a member" do
      workspace.memberships.create!(user: newcomer, role: member_role)
      post workspace_join_path(workspace, token: link.token)
      expect(response).to redirect_to(workspace_path(workspace))
    end

    it "returns the same neutral error for invalid + unauthorized cases (no info leak)" do
      # Confirms that "link doesn't exist" and "policy isn't open_link" surface
      # the same alert — don't reveal whether a specific workspace allows joins.
      workspace.update!(join_policy: "invite")
      post workspace_join_path(workspace, token: link.token)
      no_policy_alert = flash[:alert]

      post workspace_join_path(workspace, token: "totally-fake-token")
      no_link_alert = flash[:alert]

      expect(no_policy_alert).to be_present
      expect(no_link_alert).to eq(no_policy_alert)
    end
  end

  describe "GET /workspaces/:slug/joins/:token" do
    it "renders a confirmation page for a valid active link" do
      get workspace_join_path(workspace, token: link.token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(workspace.name)
    end

    it "redirects with an error for a revoked link" do
      link.revoke!
      get workspace_join_path(workspace, token: link.token)
      expect(response).to redirect_to(root_path)
    end
  end
end
