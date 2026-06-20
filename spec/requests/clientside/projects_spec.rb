require "rails_helper"

RSpec.describe "Clientside projects", type: :request do
  let(:client) { create(:user) }
  let(:access) { create(:client_access, user: client) } # project has clientside_enabled: true (factory)
  let(:project) { access.project }

  before { access; sign_in(client) }

  it "lists the projects the user is a client of" do
    get clientside_projects_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(project.name)
  end

  it "shows a project's client area with only client-visible resources" do
    visible = create(:resource, project: project, status: "published", shared_with_client: true)
    hidden = create(:resource, project: project, status: "published", shared_with_client: false)
    get clientside_project_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(visible.title)
    expect(response.body).not_to include(hidden.title)
  end

  it "redirects a non-client away from a project they have no access to" do
    other = create(:project, clientside_enabled: true)
    get clientside_project_path(other)
    expect(response).to redirect_to(clientside_projects_path)
  end

  it "blocks the area when Clientside is turned off" do
    project.update!(clientside_enabled: false)
    get clientside_project_path(project)
    expect(response).to redirect_to(clientside_projects_path)
  end
end
