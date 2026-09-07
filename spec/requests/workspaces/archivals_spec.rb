require "rails_helper"

# Archive is a state, so it is a singular resource: POST archives, DELETE
# restores. Replaced the PATCH :archive / :unarchive member actions (#1007).
RSpec.describe "Workspace Archival", type: :request do
  describe "unauthenticated access" do
    it "redirects POST /workspaces/:slug/archival to sign in" do
      post workspace_archival_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }
    let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

    before { sign_in(user) }

    describe "POST /workspaces/:slug/archival" do
      it "archives the workspace and redirects to the index" do
        post workspace_archival_path(workspace)
        expect(workspace.reload).to be_archived
        expect(response).to redirect_to(workspaces_path)
        expect(flash[:notice]).to eq(I18n.t("workspaces.archivals.create.success"))
      end

      it "denies non-owners" do
        member = create(:user)
        create(:membership, user: member, workspace: workspace)
        sign_in(member)
        post workspace_archival_path(workspace)
        expect(workspace.reload).not_to be_archived
      end
    end

    describe "DELETE /workspaces/:slug/archival" do
      it "restores an archived workspace and redirects to it" do
        workspace.archive!
        delete workspace_archival_path(workspace)
        expect(workspace.reload).not_to be_archived
        expect(response).to redirect_to(workspace_path(workspace))
        expect(flash[:notice]).to eq(I18n.t("workspaces.archivals.destroy.success"))
      end

      it "denies non-owners" do
        workspace.archive!
        member = create(:user)
        create(:membership, user: member, workspace: workspace)
        sign_in(member)
        delete workspace_archival_path(workspace)
        expect(workspace.reload).to be_archived
      end
    end
  end
end
