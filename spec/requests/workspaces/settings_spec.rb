require "rails_helper"

RSpec.describe "Workspace Settings", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/settings/edit to sign in" do
      get edit_workspace_settings_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    describe "GET /workspaces/:workspace_slug/settings/edit" do
      it "renders the settings form" do
        workspace = create(:workspace)
        sign_in_as_owner_of(workspace)
        get edit_workspace_settings_path(workspace)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /workspaces/:workspace_slug/settings" do
      it "updates max_members" do
        workspace = create(:workspace)
        sign_in_as_owner_of(workspace)
        patch workspace_settings_path(workspace), params: { workspace: { max_members: 10 } }
        expect(workspace.reload.max_members).to eq(10)
      end

      it "redirects with success message" do
        workspace = create(:workspace)
        sign_in_as_owner_of(workspace)
        patch workspace_settings_path(workspace), params: { workspace: { max_members: 10 } }
        expect(response).to redirect_to(edit_workspace_settings_path(workspace))
        expect(flash[:notice]).to eq(I18n.t("workspaces.settings.update.success"))
      end
    end

    describe "PATCH with invalid params" do
      it "returns unprocessable entity for zero max_members" do
        workspace = create(:workspace)
        sign_in_as_owner_of(workspace)
        patch workspace_settings_path(workspace), params: { workspace: { max_members: 0 } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "authorization" do
      it "rejects non-owner/admin access" do
        workspace = create(:workspace)
        sign_in_as_owner_of(workspace)
        viewer = create(:user)
        create(:membership, :viewer, user: viewer, workspace: workspace)
        sign_in(viewer)
        get edit_workspace_settings_path(workspace)
        expect(response).to redirect_to(workspace_path(workspace))
      end
    end
  end
end
