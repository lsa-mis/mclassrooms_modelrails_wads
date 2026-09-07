require "rails_helper"

# The logo picker hub is the show of a singular logo resource; it replaced
# the GET :identity_picker_hub member action (#1007). Saves still post to
# workspaces#update, which is where the logo lives.
RSpec.describe "Workspace Logo", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/logo to sign in" do
      get workspace_logo_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }
    let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

    before { sign_in(user) }

    describe "GET /workspaces/:slug/logo" do
      it "renders the picker hub partial" do
        get workspace_logo_path(workspace, source: "initials"),
            headers: { "Turbo-Frame" => "identity-picker-hub" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("identity-picker-hub")
      end

      it "falls back to the current logo source for an invalid source param" do
        get workspace_logo_path(workspace, source: "gravatar"),
            headers: { "Turbo-Frame" => "identity-picker-hub" }
        expect(response).to have_http_status(:ok)
      end

      it "denies a member without manage_settings" do
        member = create(:user)
        create(:membership, user: member, workspace: workspace)
        sign_in(member)
        get workspace_logo_path(workspace)
        expect(response).not_to have_http_status(:ok)
      end
    end
  end
end
