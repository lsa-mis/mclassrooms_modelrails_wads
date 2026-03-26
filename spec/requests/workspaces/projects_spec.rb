require "rails_helper"

RSpec.describe "Workspace Projects", type: :request do
  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }
  let!(:ws_membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before do
    Current.workspace = workspace
    sign_in(user)
  end

  describe "GET /workspaces/:workspace_slug/projects" do
    it "lists projects" do
      project = create(:project, workspace: workspace, created_by: user)
      create(:project_membership, :creator, project: project, user: user)
      get workspace_projects_path(workspace)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(project.name)
    end
  end

  describe "GET /workspaces/:workspace_slug/projects/new" do
    it "renders the new form" do
      get new_workspace_project_path(workspace)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /workspaces/:workspace_slug/projects" do
    it "creates a project and assigns creator role" do
      expect {
        post workspace_projects_path(workspace), params: { project: { name: "New Project" } }
      }.to change(Project, :count).by(1)

      project = Project.last
      pm = project.project_memberships.find_by(user: user)
      expect(pm).to be_creator
    end

    it "enforces max_projects" do
      workspace.update!(max_projects: 1)
      create(:project, workspace: workspace, created_by: user)
      post workspace_projects_path(workspace), params: { project: { name: "Over Limit" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /workspaces/:workspace_slug/projects/:slug" do
    let(:project) { create(:project, workspace: workspace, created_by: user) }
    before { create(:project_membership, :creator, project: project, user: user) }

    it "shows the project" do
      get workspace_project_path(workspace, project)
      expect(response).to have_http_status(:ok)
    end

    it "denies non-project-members" do
      other = create(:user)
      create(:membership, user: other, workspace: workspace)
      sign_in(other)
      get workspace_project_path(workspace, project)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH /workspaces/:workspace_slug/projects/:slug" do
    let(:project) { create(:project, workspace: workspace, created_by: user) }
    before { create(:project_membership, :creator, project: project, user: user) }

    it "updates the project" do
      patch workspace_project_path(workspace, project), params: { project: { name: "Updated" } }
      expect(project.reload.name).to eq("Updated")
    end
  end

  describe "DELETE /workspaces/:workspace_slug/projects/:slug" do
    let(:project) { create(:project, workspace: workspace, created_by: user) }
    before { create(:project_membership, :creator, project: project, user: user) }

    it "soft deletes the project" do
      delete workspace_project_path(workspace, project)
      expect(project.reload).to be_discarded
    end
  end
end
