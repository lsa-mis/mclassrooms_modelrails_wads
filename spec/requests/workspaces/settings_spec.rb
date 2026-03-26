require "rails_helper"

RSpec.describe "Workspace Settings", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  describe "GET /workspaces/:workspace_slug/settings/edit" do
    it "renders the settings form" do
      get edit_workspace_settings_path(workspace)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /workspaces/:workspace_slug/settings" do
    it "updates max_members" do
      patch workspace_settings_path(workspace), params: { workspace: { max_members: 10 } }
      expect(workspace.reload.max_members).to eq(10)
    end

    it "updates max_projects" do
      patch workspace_settings_path(workspace), params: { workspace: { max_projects: 5 } }
      expect(workspace.reload.max_projects).to eq(5)
    end

    it "redirects with success message" do
      patch workspace_settings_path(workspace), params: { workspace: { max_members: 10 } }
      expect(response).to redirect_to(edit_workspace_settings_path(workspace))
    end
  end

  describe "authorization" do
    it "rejects non-owner/admin access" do
      viewer_role = Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" }
      viewer = create(:user)
      create(:membership, user: viewer, workspace: workspace, role: viewer_role)
      sign_in(viewer)
      get edit_workspace_settings_path(workspace)
      expect(response).to redirect_to(workspace_path(workspace))
    end
  end
end
