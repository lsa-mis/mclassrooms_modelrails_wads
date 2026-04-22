require "rails_helper"

RSpec.describe "Global RecordNotFound handling", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  describe "HTML request for nonexistent record" do
    it "redirects with an alert instead of raising 500" do
      delete workspace_member_path(workspace, id: 999_999)
      expect(response).to redirect_to(request.referer || root_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("errors.not_found"))
    end
  end

  describe "Turbo Stream request for nonexistent record" do
    it "returns 404 with an error toast" do
      delete workspace_member_path(workspace, id: 999_999),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("toast")
    end
  end

  describe "JSON request for nonexistent record" do
    it "returns 404 JSON" do
      delete workspace_member_path(workspace, id: 999_999),
        headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq(I18n.t("errors.not_found"))
    end
  end

  describe "existing local rescues still take precedence" do
    it "WorkspaceScoped redirects to workspaces_path for nonexistent workspace" do
      get workspace_members_path(workspace_slug: "nonexistent-slug")
      expect(response).to redirect_to(workspaces_path)
    end
  end
end
