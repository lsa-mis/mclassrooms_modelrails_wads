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
    # Force a slug that cannot collide with the client's own `project`. Project
    # slugs are only workspace-unique (Sluggable), and the factory's small
    # Faker::App.name pool occasionally names `other` identically to `project`,
    # in a different workspace. When the slugs match, the allowlist-scoped
    # lookup in Clientside::BaseController#set_client_project resolves to
    # `project` (which IS accessible) and no redirect happens — the order-
    # dependent flake tracked in #456. The record id guarantees distinctness.
    other.update_column(:slug, "no-access-#{other.id}")
    get clientside_project_path(other)
    expect(response).to redirect_to(clientside_projects_path)
  end

  it "blocks the area when Clientside is turned off" do
    project.update!(clientside_enabled: false)
    get clientside_project_path(project)
    expect(response).to redirect_to(clientside_projects_path)
  end
end
