require "rails_helper"

RSpec.describe "Project Resources", type: :request do
  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }
  let!(:ws_membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let(:project) { create(:project, workspace: workspace, created_by: user) }
  let!(:creator_pm) { create(:project_membership, :creator, project: project, user: user) }

  before do
    Current.workspace = workspace
    Current.project = project
    sign_in(user)
  end

  describe "GET index" do
    it "lists project resources" do
      resource = create(:resource, project: project, created_by: user)
      get workspace_project_resources_path(workspace, project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(resource.title)
    end
  end

  describe "GET new" do
    it "renders the new document form" do
      get new_workspace_project_resource_path(workspace, project)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST create" do
    it "creates a document resource" do
      expect {
        post workspace_project_resources_path(workspace, project), params: {
          resource: { title: "My Document", type: "Document" },
          document: { body: "Some content" }
        }
      }.to change(Resource, :count).by(1)
        .and change(Document, :count).by(1)
    end

    it "assigns created_by to current user" do
      post workspace_project_resources_path(workspace, project), params: {
        resource: { title: "My Document", type: "Document" },
        document: { body: "Content" }
      }
      resource = Resource.find_by!(title: "My Document")
      expect(resource.created_by).to eq(user)
    end

    it "defaults to draft status" do
      post workspace_project_resources_path(workspace, project), params: {
        resource: { title: "Draft Doc", type: "Document" },
        document: { body: "Draft" }
      }
      resource = Resource.find_by!(title: "Draft Doc")
      expect(resource).to be_draft
    end

    it "rejects invalid resource type" do
      post workspace_project_resources_path(workspace, project), params: {
        resource: { title: "Bad Type", type: "User" },
        document: { body: "Content" }
      }
      expect(response).to redirect_to(workspace_project_resources_path(workspace, project))
    end
  end

  describe "GET show" do
    let!(:resource) { create(:resource, project: project, created_by: user) }

    it "displays the resource" do
      get workspace_project_resource_path(workspace, project, resource)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(resource.title)
    end

    it "denies non-project-members" do
      outsider = create(:user)
      create(:membership, user: outsider, workspace: workspace)
      sign_in(outsider)
      get workspace_project_resource_path(workspace, project, resource)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH update" do
    let!(:resource) { create(:resource, project: project, created_by: user) }

    it "updates the resource title" do
      patch workspace_project_resource_path(workspace, project, resource), params: {
        resource: { title: "Updated Title" }
      }
      expect(resource.reload.title).to eq("Updated Title")
    end
  end

  describe "DELETE destroy" do
    let!(:resource) { create(:resource, project: project, created_by: user) }

    it "soft deletes the resource" do
      delete workspace_project_resource_path(workspace, project, resource)
      expect(resource.reload).to be_discarded
    end
  end

  describe "PATCH reposition" do
    let!(:resource) { create(:resource, project: project, created_by: user, position: 0) }
    let!(:resource2) { create(:resource, project: project, created_by: user, position: 1) }
    let!(:resource3) { create(:resource, project: project, created_by: user, position: 2) }
    let!(:resource4) { create(:resource, project: project, created_by: user, position: 3) }

    it "updates the resource position" do
      patch reposition_workspace_project_resource_path(workspace, project, resource), params: {
        resource: { position: 3 }
      }
      expect(resource.reload.position).to eq(3)
    end

    it "clamps negative position to 0" do
      patch reposition_workspace_project_resource_path(workspace, project, resource), params: {
        resource: { position: -5 }
      }
      expect(resource.reload.position).to eq(0)
    end
  end

  describe "authorization" do
    it "denies viewers from creating" do
      viewer = create(:user)
      create(:membership, user: viewer, workspace: workspace)
      create(:project_membership, :viewer, project: project, user: viewer)
      sign_in(viewer)
      post workspace_project_resources_path(workspace, project), params: {
        resource: { title: "Nope", type: "Document" },
        document: { body: "Nope" }
      }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "authorization - editor cannot update others' resources" do
    let(:editor) { create(:user) }
    let!(:editor_ws) { create(:membership, user: editor, workspace: workspace) }
    let!(:editor_pm) { create(:project_membership, project: project, user: editor) }
    let!(:resource) { create(:resource, project: project, created_by: user) }

    it "denies editor from updating a resource they didn't create" do
      sign_in(editor)
      patch workspace_project_resource_path(workspace, project, resource), params: {
        resource: { title: "Hacked Title" }
      }
      expect(resource.reload.title).not_to eq("Hacked Title")
      expect(response).to have_http_status(:redirect)
    end
  end
end
