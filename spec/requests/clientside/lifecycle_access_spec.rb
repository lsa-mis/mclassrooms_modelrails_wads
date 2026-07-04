# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Clientside lifecycle access", type: :request do
  let(:client) { create(:user) }
  let(:access) { create(:client_access, user: client) }
  let(:project) { access.project }
  let(:workspace) { project.workspace }

  before { access; sign_in(client) }

  context "project's workspace is suspended" do
    before { workspace.suspend! }

    it "excludes it from the clientside index" do
      get clientside_projects_path
      expect(response.body).not_to include(clientside_project_path(project))
      expect(response.body).not_to match(/archived|deleted|locked|suspended/i)
    end

    it "redirects show to the index with the generic no-access message" do
      get clientside_project_path(project)
      expect(response).to redirect_to(clientside_projects_path)
      expect(flash[:alert]).to eq(I18n.t("clientside.area.no_access"))
      expect(flash[:alert]).not_to match(/archived|deleted|locked|suspended/i)
    end
  end

  context "project is discarded" do
    before { project.discard! }

    it "excludes it from the index and blocks show with generic no-access" do
      get clientside_projects_path
      expect(response.body).not_to include(clientside_project_path(project))
      expect(response.body).not_to match(/archived|deleted|locked|suspended/i)

      get clientside_project_path(project)
      expect(response).to redirect_to(clientside_projects_path)
      expect(flash[:alert]).to eq(I18n.t("clientside.area.no_access"))
      expect(flash[:alert]).not_to match(/archived|deleted|locked|suspended/i)
    end
  end

  context "project's workspace is discarded" do
    before { workspace.discard! }

    it "excludes it from the index and blocks show with generic no-access" do
      get clientside_projects_path
      expect(response.body).not_to include(clientside_project_path(project))
      expect(response.body).not_to match(/archived|deleted|locked|suspended/i)

      get clientside_project_path(project)
      expect(response).to redirect_to(clientside_projects_path)
      expect(flash[:alert]).to eq(I18n.t("clientside.area.no_access"))
      expect(flash[:alert]).not_to match(/archived|deleted|locked|suspended/i)
    end
  end

  context "project's workspace is archived" do
    before { workspace.archive! }

    it "still appears in the index and show renders" do
      get clientside_projects_path
      expect(response.body).to include(clientside_project_path(project))

      get clientside_project_path(project)
      expect(response).to have_http_status(:ok)
    end
  end
end
