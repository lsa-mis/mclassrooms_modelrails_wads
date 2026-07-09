# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Clientside resources", type: :request do
  let(:client) { create(:user) }
  let(:access) { create(:client_access, user: client) }
  let(:project) { access.project }

  before { access; sign_in(client) }

  it "shows a client-visible resource" do
    resource = create(:resource, project: project, status: "published", shared_with_client: true)
    get clientside_project_resource_path(project, resource)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(resource.title)
  end

  it "refuses a draft resource" do
    draft = create(:resource, project: project, status: "draft", shared_with_client: true)
    get clientside_project_resource_path(project, draft)
    expect(response).to redirect_to(clientside_project_path(project))
  end

  it "refuses an unshared resource" do
    unshared = create(:resource, project: project, status: "published", shared_with_client: false)
    get clientside_project_resource_path(project, unshared)
    expect(response).to redirect_to(clientside_project_path(project))
  end

  it "refuses access for a non-client" do
    # Pin a distinctive name so the slug can't collide with the client's own
    # accessible project. Project slugs are only unique per workspace, and both
    # projects draw Faker::App.name — a same-slug draw would make
    # set_client_project resolve the client's OWN project by the shared slug and
    # redirect there instead of the index (CI flake, same species as the
    # membership Faker-email collision).
    other = create(:project, clientside_enabled: true, name: "Unrelated Non-Client Project")
    resource = create(:resource, project: other, status: "published", shared_with_client: true)
    get clientside_project_resource_path(other, resource)
    expect(response).to redirect_to(clientside_projects_path)
  end
end
