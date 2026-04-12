require "rails_helper"

RSpec.describe "Workspace Brandings", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/branding/edit to sign in" do
      get edit_workspace_branding_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }
    let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

    before { sign_in(user) }

    describe "GET /workspaces/:workspace_slug/branding/edit" do
      it "renders the branding form" do
        get edit_workspace_branding_path(workspace)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding" do
      it "updates the primary color" do
        patch workspace_branding_path(workspace), params: {
          workspace: { primary_color: "#6366f1" }
        }
        expect(workspace.reload.primary_color).to eq("#6366f1")
      end

      it "uploads a logo" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch workspace_branding_path(workspace), params: {
          workspace: { logo: file }
        }
        expect(workspace.reload.logo).to be_attached
      end

      it "redirects with success message" do
        patch workspace_branding_path(workspace), params: {
          workspace: { primary_color: "#6366f1" }
        }
        expect(response).to redirect_to(edit_workspace_branding_path(workspace))
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding with logo and color together" do
      it "updates both logo and color" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch workspace_branding_path(workspace), params: {
          workspace: { logo: file, primary_color: "#0d9488" }
        }
        workspace.reload
        expect(workspace.logo).to be_attached
        expect(workspace.primary_color).to eq("#0d9488")
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding via upload modal" do
      it "uploads a logo and redirects to edit page" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch workspace_branding_path(workspace), params: { workspace: { logo: file } }
        expect(workspace.reload.logo).to be_attached
        expect(response).to redirect_to(edit_workspace_branding_path(workspace))
      end

      it "removes the logo when remove_image is sent" do
        workspace.logo.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "logo.png", content_type: "image/png"
        )
        patch workspace_branding_path(workspace), params: { remove_image: "1" }
        expect(workspace.reload.logo).not_to be_attached
        expect(response).to redirect_to(edit_workspace_branding_path(workspace))
      end
    end

    describe "authorization" do
      it "rejects non-owner/admin access" do
        viewer_role = Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" }
        viewer = create(:user)
        create(:membership, user: viewer, workspace: workspace, role: viewer_role)
        sign_in(viewer)
        get edit_workspace_branding_path(workspace)
        expect(response).to redirect_to(workspace_path(workspace))
      end
    end
  end
end
