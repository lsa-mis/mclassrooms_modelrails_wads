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

      # Regression guard: four real N+1s on this surface survived per-task
      # spec-compliance + cross-task code-quality + manual security/N+1 reviews
      # before bin/dev's Bullet panel caught them at runtime. Bullet running
      # against a multi-row end-to-end render is the only thing that reliably
      # exposes eager-load shape regressions on workspaces#index.
      #
      # Mechanism: Bullet.raise = true (config/environments/test.rb) raises
      # mid-request via the Bullet::Rack middleware as soon as the detector
      # sees an N+1 / unused-eager-loading hit. The Rack middleware also
      # wraps each HTTP request in start_request/end_request, which clears
      # the notification_collector before control returns to the spec — so
      # post-hoc Bullet.warnings inspection is not possible from a request
      # spec. The right pattern here is: render with enough rows to expose
      # the eager-load shape and let Bullet.raise fail the example.
      #
      # The single-row examples above don't reliably trip Bullet because
      # NPlusOne detection is threshold-based. This multi-row fixture is
      # what gives the guard its teeth — any future change that breaks
      # the eager-load chain (controller includes, sidebar preload, the
      # workspace_icon_for owner-fallback) fails HERE at CI time.
      it "renders without N+1 queries (regression guard)" do
        # Three workspaces with varying last_accessed_at exercise the full
        # row-render path: pinned-current row + others list, policy checks
        # per row, workspace_icon_for fallback (which walks memberships to
        # find the owner role when no logo is attached).
        workspaces = (1..3).map do |i|
          ws = create(:workspace, name: "Workspace #{i}")
          create(:membership, :owner, user: user, workspace: ws, last_accessed_at: i.days.ago)
          ws
        end

        get workspaces_path

        # If Bullet detected an N+1 mid-request it would have already raised
        # and the example would be a failure, not a passed assertion. These
        # expectations confirm the render actually completed end-to-end with
        # multiple rows, which is what gives the Bullet guard its coverage.
        expect(response).to have_http_status(:ok)
        workspaces.each do |ws|
          expect(response.body).to include(CGI.escapeHTML(ws.name))
        end
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

    describe "workspace creation disabled (TENANCY_WORKSPACE_CREATION=disabled)" do
      before do
        allow(Rails.configuration.x.tenancy).to receive(:workspace_creation).and_return(:disabled)
      end

      it "redirects GET /workspaces/new to root with an alert" do
        get new_workspace_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("workspaces.creation_disabled"))
      end

      it "refuses POST /workspaces" do
        expect {
          post workspaces_path, params: { workspace: { name: "Blocked Workspace" } }
        }.not_to change(Workspace, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("workspaces.creation_disabled"))
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

      it "renders the workspace Profile destination" do
        get edit_workspace_path(workspace)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(workspace.name)
      end
    end

    describe "GET /workspaces/:slug/edit authorization" do
      it "denies plain members without manage_settings" do
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

    describe "PATCH /workspaces/:slug" do
      let(:workspace) { create(:workspace, name: "Old Name") }
      let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

      it "updates the workspace name and redirects to the Profile destination" do
        patch workspace_path(workspace), params: { workspace: { name: "New Name" } }
        expect(workspace.reload.name).to eq("New Name")
        expect(response).to redirect_to(edit_workspace_path(workspace))
      end

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
