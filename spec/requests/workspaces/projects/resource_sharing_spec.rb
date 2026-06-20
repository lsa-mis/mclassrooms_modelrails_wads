require "rails_helper"

RSpec.describe "Resource client-sharing (team side)", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) do
    create(:project, workspace: workspace, created_by: user).tap do |p|
      p.project_memberships.create!(user: user, role: "creator")
    end
  end
  let(:resource) { create(:resource, project: project, status: "published") }

  before { sign_in(user) }

  it "shows the share checkbox on edit only when Clientside is enabled" do
    project.update!(clientside_enabled: false)
    get edit_workspace_project_resource_path(workspace, project, resource)
    expect(response.body).not_to include("resource_shared_with_client")

    project.update!(clientside_enabled: true)
    get edit_workspace_project_resource_path(workspace, project, resource)
    expect(response.body).to include("resource_shared_with_client")
  end

  it "sets shared_with_client when Clientside is enabled" do
    project.update!(clientside_enabled: true)
    patch workspace_project_resource_path(workspace, project, resource),
      params: { resource: { title: resource.title, status: "published", shared_with_client: "1" } }
    expect(resource.reload.shared_with_client?).to be(true)
  end

  it "ignores shared_with_client when Clientside is disabled" do
    project.update!(clientside_enabled: false)
    patch workspace_project_resource_path(workspace, project, resource),
      params: { resource: { title: resource.title, status: "published", shared_with_client: "1" } }
    expect(resource.reload.shared_with_client?).to be(false)
  end
end
