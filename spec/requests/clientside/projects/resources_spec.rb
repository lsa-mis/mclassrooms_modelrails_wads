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
    other = create(:project, clientside_enabled: true)
    resource = create(:resource, project: other, status: "published", shared_with_client: true)
    get clientside_project_resource_path(other, resource)
    expect(response).to redirect_to(clientside_projects_path)
  end
end
