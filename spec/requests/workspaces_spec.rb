require "rails_helper"

RSpec.describe "Workspaces", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces to sign in" do
      get workspaces_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    describe "GET /workspaces" do
      it "lists the user's workspaces" do
        workspace = create(:workspace)
        create(:membership, :owner, user: user, workspace: workspace)
        get workspaces_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(CGI.escapeHTML(workspace.name))
      end

      it "does not show other users' workspaces" do
        other_workspace = create(:workspace, name: "Secret Workspace")
        get workspaces_path
        expect(response.body).not_to include("Secret Workspace")
      end

      it "does not show discarded workspaces" do
        workspace = create(:workspace)
        create(:membership, :owner, user: user, workspace: workspace)
        workspace.discard!
        get workspaces_path
        expect(response.body).not_to include(CGI.escapeHTML(workspace.name))
      end
    end

    describe "GET /workspaces/new" do
      it "renders the new form" do
        get new_workspace_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /workspaces" do
      it "creates a workspace" do
        expect {
          post workspaces_path, params: { workspace: { name: "New Workspace" } }
        }.to change(Workspace, :count).by(1)
      end

      it "assigns the creator as owner" do
        post workspaces_path, params: { workspace: { name: "New Workspace" } }
        workspace = Workspace.find_by!(name: "New Workspace")
        membership = workspace.memberships.find_by(user: user)
        expect(membership.role.slug).to eq("owner")
      end

      it "redirects to the workspace" do
        post workspaces_path, params: { workspace: { name: "New Workspace" } }
        expect(response).to redirect_to(workspace_path(Workspace.find_by!(name: "New Workspace")))
      end
    end

    describe "GET /workspaces/:slug" do
      let(:workspace) { create(:workspace) }
      let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

      it "shows the workspace" do
        get workspace_path(workspace)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(CGI.escapeHTML(workspace.name))
      end
    end

    describe "PATCH /workspaces/:slug" do
      let(:workspace) { create(:workspace) }
      let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

      it "updates the workspace name" do
        patch workspace_path(workspace), params: { workspace: { name: "Updated Name" } }
        expect(workspace.reload.name).to eq("Updated Name")
      end
    end

    describe "DELETE /workspaces/:slug" do
      let(:workspace) { create(:workspace) }
      let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

      it "soft deletes the workspace" do
        delete workspace_path(workspace)
        expect(workspace.reload).to be_discarded
      end

      it "redirects to workspaces index" do
        delete workspace_path(workspace)
        expect(response).to redirect_to(workspaces_path)
      end
    end

    describe "authorization" do
      it "rejects access to workspaces user is not a member of" do
        other_workspace = create(:workspace)
        get workspace_path(other_workspace)
        expect(response).to redirect_to(workspaces_path)
      end
    end

    describe "GET /workspaces/:slug/edit" do
      let(:workspace) { create(:workspace) }
      let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

      it "redirects to the unified settings page" do
        get edit_workspace_path(workspace)
        expect(response).to redirect_to(edit_workspace_settings_path(workspace))
      end
    end

    describe "GET /workspaces/:slug/edit authorization" do
      it "denies members without manage_workspace" do
        workspace = create(:workspace)
        member = create(:user)
        create(:membership, user: member, workspace: workspace)
        sign_in(member)
        get edit_workspace_path(workspace)
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "POST /workspaces with invalid params" do
      it "returns unprocessable entity for blank name" do
        post workspaces_path, params: { workspace: { name: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "PATCH /workspaces/:slug with invalid params" do
      let(:workspace) { create(:workspace) }
      let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

      it "returns unprocessable entity for blank name" do
        patch workspace_path(workspace), params: { workspace: { name: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "authorization" do
      let(:workspace) { create(:workspace) }
      let(:member) { create(:user) }
      let!(:member_membership) { create(:membership, user: member, workspace: workspace) }

      it "denies non-owner from updating workspace" do
        sign_in(member)
        patch workspace_path(workspace), params: { workspace: { name: "Hacked" } }
        expect(response).to have_http_status(:redirect)
        expect(workspace.reload.name).not_to eq("Hacked")
      end

      it "denies non-owner from destroying workspace" do
        sign_in(member)
        delete workspace_path(workspace)
        expect(workspace.reload).not_to be_discarded
      end
    end
  end
end
