require "rails_helper"

RSpec.describe "Project Clientside settings", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end

  before { sign_in(user) }

  it "renders the toggle form" do
    get edit_workspace_project_clientside_path(workspace, project)
    expect(response).to have_http_status(:ok)
  end

  it "enables Clientside" do
    patch workspace_project_clientside_path(workspace, project),
      params: { project: { clientside_enabled: "1" } }
    expect(project.reload.clientside_enabled?).to be(true)
    expect(response).to redirect_to(edit_workspace_project_clientside_path(workspace, project))
  end

  context "as a project member who is not the creator" do
    let(:viewer) { create(:user) }
    let!(:viewer_role) do
      Role.find_or_create_by!(slug: "viewer", workspace_id: nil) do |r|
        r.name = "Viewer"
        r.permissions = {}
      end
    end

    before do
      workspace.memberships.create!(user: viewer, role: viewer_role)
      project.project_memberships.create!(user: viewer, role: "viewer")
      sign_in(viewer)
    end

    it "denies access (redirect, unchanged)" do
      patch workspace_project_clientside_path(workspace, project),
        params: { project: { clientside_enabled: "1" } }
      expect(response).to have_http_status(:redirect)
      expect(project.reload.clientside_enabled?).to be(false)
    end
  end
end
