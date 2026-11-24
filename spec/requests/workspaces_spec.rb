require "rails_helper"

RSpec.describe "Workspaces", type: :request do
  def signed_in_user
    user = create(:user)
    sign_in(user)
    user
  end

  def signed_in_owned_workspace(*traits, **attrs)
    user = create(:user)
    workspace = create(:workspace, *traits, **attrs)
    sign_in_as_owner_of(workspace, user: user)
    workspace
  end

  def owned_workspace(user, *traits, **attrs)
    workspace = create(:workspace, *traits, **attrs)
    create(:membership, :owner, user: user, workspace: workspace)
    workspace
  end

  def sign_in_member_of(workspace)
    member = create(:user)
    create(:membership, user: member, workspace: workspace)
    sign_in(member)
    member
  end

  def avatar_file
    fixture_file_upload("avatar.png", "image/png")
  end

  def turbo_headers
    { "Accept" => "text/vnd.turbo-stream.html" }
  end

  describe "unauthenticated access" do
    it "redirects GET /workspaces to sign in" do
      get workspaces_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    describe "GET /workspaces" do
      it "lists the user's workspaces" do
        workspace = signed_in_owned_workspace
        get workspaces_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(CGI.escapeHTML(workspace.name))
      end

      # One create action, in the header (#1092).
      it "offers one route to the new-workspace page, not two" do
        signed_in_owned_workspace

        get workspaces_path

        expect(Capybara.string(response.body)).to have_link(href: new_workspace_path, count: 1)
      end

      # The container owns the row chrome, one padding across all three lists (#1119).
      it "gives a locked row the same chrome as the rows beside it" do
        user = signed_in_user
        held = owned_workspace(user, name: "Held Co")
        owned_workspace(user, name: "Fine Co")
        held.suspend!

        get workspaces_path
        page = Capybara.string(response.body)

        locked = page.find("[data-test='locked-workspace-row']")
        expect(locked[:class].to_s.split).to include("p-3", "rounded-lg", "border"),
          "the locked row does not share the chrome of the rows it sits with"
      end

      it "does not show other users' workspaces" do
        signed_in_user
        create(:workspace, name: "Secret Workspace")
        get workspaces_path
        expect(response.body).not_to include("Secret Workspace")
      end

      # #765: the overlay link carries its own focus-ring outline, the li paints no
      # shared focus-within ring, and the link names itself via aria-labelledby.
      it "gives the workspace row's overlay link the focus contract and a labelledby name" do
        workspace = signed_in_owned_workspace(name: "Focusable Co")
        get workspaces_path
        page = Capybara.string(response.body)

        row = page.find("li[data-name='focusable co']")
        expect(row[:class]).not_to include("focus-within:ring")
        overlay = row.find("a[href='#{workspace_path(workspace)}']", match: :first)
        expect(overlay[:class].split).to include("focus-ring")
        expect(overlay[:class]).not_to include("outline-none")
        expect(overlay["aria-labelledby"]).to be_present
        expect(row.find("##{overlay["aria-labelledby"]}").text.strip).to eq("Focusable Co")
      end

      it "does not show discarded workspaces" do
        workspace = signed_in_owned_workspace
        workspace.discard!
        get workspaces_path
        expect(response.body).not_to include(CGI.escapeHTML(workspace.name))
      end

      # Regression guard: Bullet.raise fails the request on an N+1 only when several
      # rows render, so this multi-row fixture is what gives the guard its teeth.
      it "renders without N+1 queries (regression guard)" do
        user = signed_in_user
        workspaces = (1..3).map do |i|
          ws = create(:workspace, name: "Workspace #{i}")
          create(:membership, :owner, user: user, workspace: ws, last_accessed_at: i.days.ago)
          ws
        end

        get workspaces_path

        expect(response).to have_http_status(:ok)
        workspaces.each do |ws|
          expect(response.body).to include(CGI.escapeHTML(ws.name))
        end
      end
    end

    describe "GET /workspaces/new" do
      it "renders the new form" do
        signed_in_user
        get new_workspace_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /workspaces" do
      it "creates a workspace" do
        signed_in_user
        expect {
          post workspaces_path, params: { workspace: { name: "New Workspace" } }
        }.to change(Workspace, :count).by(1)
      end

      it "assigns the creator as owner" do
        user = signed_in_user
        post workspaces_path, params: { workspace: { name: "New Workspace" } }
        workspace = Workspace.find_by!(name: "New Workspace")
        membership = workspace.memberships.find_by(user: user)
        expect(membership.role.slug).to eq("owner")
      end

      it "redirects to the workspace and says it was created" do
        signed_in_user
        post workspaces_path, params: { workspace: { name: "New Workspace" } }
        expect(response).to redirect_to(workspace_path(Workspace.find_by!(name: "New Workspace")))
        # By key, not by sentence: which key was selected is the point (#526).
        expect(flash[:notice]).to eq(I18n.t("workspaces.create.success"))
      end
    end

    describe "workspace creation disabled (TENANCY_WORKSPACE_CREATION=disabled)" do
      before do
        allow(Rails.configuration.x.tenancy).to receive(:workspace_creation).and_return(:disabled)
      end

      it "redirects GET /workspaces/new to root with an alert" do
        signed_in_user
        get new_workspace_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("workspaces.creation_disabled"))
      end

      it "refuses POST /workspaces" do
        signed_in_user
        expect {
          post workspaces_path, params: { workspace: { name: "Blocked Workspace" } }
        }.not_to change(Workspace, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("workspaces.creation_disabled"))
      end
    end

    describe "GET /workspaces/:slug" do
      it "shows the workspace" do
        workspace = signed_in_owned_workspace
        get workspace_path(workspace)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(CGI.escapeHTML(workspace.name))
      end
    end

    describe "PATCH /workspaces/:slug" do
      it "updates the workspace name and says the profile was updated" do
        workspace = signed_in_owned_workspace
        patch workspace_path(workspace), params: { workspace: { name: "Updated Name" } }
        expect(workspace.reload.name).to eq("Updated Name")
        expect(flash[:notice]).to eq(I18n.t("workspaces.update.success"))
      end
    end

    describe "PATCH /workspaces/:slug — identity (logo/color) params" do
      it "attaches a logo sent under the avatar alias (identity-picker wire protocol)" do
        workspace = signed_in_owned_workspace
        patch workspace_path(workspace), params: { avatar: avatar_file }
        workspace.reload
        expect(workspace.logo).to be_attached
        expect(workspace.logo_source).to eq("upload")
      end

      it "attaches a logo sent under the logo key" do
        workspace = signed_in_owned_workspace
        patch workspace_path(workspace), params: { logo: avatar_file }
        expect(workspace.reload.logo).to be_attached
      end

      it "attaches the original under the avatar_original alias and stores crop coordinates" do
        workspace = signed_in_owned_workspace
        patch workspace_path(workspace), params: {
          avatar: avatar_file,
          avatar_original: fixture_file_upload("avatar.png", "image/png"),
          crop_coordinates: '{"x":10,"y":20,"w":100,"h":100}'
        }
        workspace.reload
        expect(workspace.logo_original).to be_attached
        expect(workspace.logo_original.blob.metadata["crop"]).to eq("x" => 10, "y" => 20, "w" => 100, "h" => 100)
      end

      it "updates primary_color and logo_source from top-level params" do
        workspace = signed_in_owned_workspace
        patch workspace_path(workspace), params: { avatar_source: "initials", primary_color: "270" }
        workspace.reload
        expect(workspace.primary_color).to eq(270)
        expect(workspace.logo_source).to eq("initials")
      end

      context "with a logo attached" do
        it "purges logo and original when the source switches away from upload" do
          workspace = signed_in_owned_workspace(:with_logo)
          patch workspace_path(workspace), params: { avatar_source: "initials" }
          workspace.reload
          expect(workspace.logo).not_to be_attached
          expect(workspace.logo_original).not_to be_attached
          expect(workspace.logo_source).to eq("initials")
        end
      end

      it "rejects an unavailable source with a 403 turbo-stream toast" do
        workspace = signed_in_owned_workspace
        patch workspace_path(workspace), params: { avatar_source: "gravatar" }, headers: turbo_headers
        expect(response).to have_http_status(:forbidden)
        expect(response.body).to include(I18n.t("workspaces.brandings.source_unavailable"))
      end

      it "rejects an unavailable source with a redirect and alert for HTML" do
        workspace = signed_in_owned_workspace
        patch workspace_path(workspace), params: { avatar_source: "gravatar" }
        expect(response).to redirect_to(edit_workspace_path(workspace))
        expect(flash[:alert]).to eq(I18n.t("workspaces.brandings.source_unavailable"))
      end

      it "lets a file upload win over a stale unavailable source param (unified with user side)" do
        workspace = signed_in_owned_workspace
        patch workspace_path(workspace), params: { avatar: avatar_file, avatar_source: "gravatar" }, headers: turbo_headers
        expect(response.status).to be < 400
        workspace.reload
        expect(workspace.logo).to be_attached
        expect(workspace.logo_source).to eq("upload")
      end

      it "keeps the modal open on a crop save (file present)" do
        workspace = signed_in_owned_workspace
        patch workspace_path(workspace), params: { avatar: avatar_file }, headers: turbo_headers
        expect(response.body).not_to include("modal-closer")
      end

      it "closes the modal on a hub save (no file)" do
        workspace = signed_in_owned_workspace
        patch workspace_path(workspace), params: { avatar_source: "initials" }, headers: turbo_headers
        expect(response.body).to include("modal-closer")
      end

      context "when save fails during an identity update" do
        # primary_color inclusion is 0..360, so 999 always fails.
        it "returns 422 turbo stream and purges the newly attached logo" do
          workspace = signed_in_owned_workspace
          patch workspace_path(workspace), params: {
            avatar: avatar_file,
            avatar_original: fixture_file_upload("avatar.png", "image/png"),
            primary_color: "999"
          }, headers: turbo_headers
          expect(response).to have_http_status(:unprocessable_content)
          workspace.reload
          expect(workspace.logo).not_to be_attached
          expect(workspace.logo_original).not_to be_attached
          expect(workspace.primary_color).not_to eq(999)
        end

        it "fails and purges the new logo when the name is blank" do
          workspace = signed_in_owned_workspace
          patch workspace_path(workspace), params: { avatar: avatar_file, workspace: { name: "" } }, headers: turbo_headers
          expect(response).to have_http_status(:unprocessable_content)
          expect(workspace.reload.logo).not_to be_attached
        end
      end

      it "ignores a non-scalar name (strong params drop it)" do
        workspace = signed_in_owned_workspace
        original_name = workspace.name
        patch workspace_path(workspace), params: { workspace: { name: { foo: "bar" } } }
        expect(workspace.reload.name).to eq(original_name)
      end
    end

    describe "PATCH /workspaces/:slug rate limiting" do
      # An over-limit count from Rails.cache.increment fires the limiter without a
      # persistent cache; stub after sign-in so the login itself is not limited.
      def exceed_rate_limit
        allow(Rails.cache).to receive(:increment).and_return(21)
      end

      it "returns a 429 turbo-stream toast once the limit is exceeded" do
        workspace = signed_in_owned_workspace
        exceed_rate_limit
        patch workspace_path(workspace), params: { workspace: { name: "Renamed" } },
              headers: turbo_headers

        expect(response).to have_http_status(:too_many_requests)
        expect(response.body).to include(I18n.t("workspaces.update.rate_limited"))
        expect(workspace.reload.name).not_to eq("Renamed")
      end

      it "redirects with an alert for HTML requests" do
        workspace = signed_in_owned_workspace
        exceed_rate_limit
        patch workspace_path(workspace), params: { workspace: { name: "Renamed" } }

        expect(response).to redirect_to(workspaces_path)
        expect(flash[:alert]).to eq(I18n.t("workspaces.update.rate_limited"))
      end
    end

    # The logo picker hub moved to spec/requests/workspaces/logos_spec.rb with the resource (#1007).

    describe "DELETE /workspaces/:slug" do
      it "soft deletes the workspace" do
        workspace = signed_in_owned_workspace
        delete workspace_path(workspace)
        expect(workspace.reload).to be_discarded
      end

      it "redirects to workspaces index and says it was deleted" do
        workspace = signed_in_owned_workspace
        delete workspace_path(workspace)
        expect(response).to redirect_to(workspaces_path)
        expect(flash[:notice]).to eq(I18n.t("workspaces.destroy.success"))
      end
    end

    # Archive/restore moved to spec/requests/workspaces/archivals_spec.rb with the resource (#1007).

    describe "DELETE from the archived state" do
      it "soft deletes an archived workspace" do
        workspace = signed_in_owned_workspace
        workspace.archive!
        delete workspace_path(workspace)
        expect(workspace.reload).to be_discarded
      end
    end

    describe "authorization" do
      it "rejects access to workspaces user is not a member of" do
        signed_in_user
        other_workspace = create(:workspace)
        get workspace_path(other_workspace)
        expect(response).to redirect_to(workspaces_path)
      end
    end

    describe "GET /workspaces/:slug/edit" do
      it "renders the workspace Profile destination" do
        workspace = signed_in_owned_workspace
        get edit_workspace_path(workspace)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(CGI.escapeHTML(workspace.name))
      end
    end

    describe "GET /workspaces/:slug/edit authorization" do
      it "denies plain members without manage_settings" do
        workspace = create(:workspace)
        sign_in_member_of(workspace)
        get edit_workspace_path(workspace)
        expect(response).to have_http_status(:redirect)
      end
    end

    # Through the real render: the fix counts only if the shipped markup changed (#1153).
    describe "the workspace nav's Settings link" do
      it "points a Member at a page they can open, not the one they are refused" do
        workspace = create(:workspace, personal: false)
        sign_in_member_of(workspace)

        get workspace_path(workspace)

        expect(response.body).to include(workspace_members_path(workspace))
        expect(response.body).not_to include("href=\"#{edit_workspace_path(workspace)}\""),
          "the nav still offers a Member the Profile page, which ProfilePolicy refuses them"
      end

      it "still points an Owner at the Profile page" do
        workspace = signed_in_owned_workspace(personal: false)

        get workspace_path(workspace)

        expect(response.body).to include("href=\"#{edit_workspace_path(workspace)}\"")
      end
    end

    describe "POST /workspaces with invalid params" do
      it "returns unprocessable entity for blank name" do
        signed_in_user
        post workspaces_path, params: { workspace: { name: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "PATCH /workspaces/:slug" do
      it "updates the workspace name and redirects to the Profile destination" do
        workspace = signed_in_owned_workspace(name: "Old Name")
        patch workspace_path(workspace), params: { workspace: { name: "New Name" } }
        expect(workspace.reload.name).to eq("New Name")
        expect(response).to redirect_to(edit_workspace_path(workspace))
      end

      it "returns unprocessable entity for blank name" do
        workspace = signed_in_owned_workspace(name: "Old Name")
        patch workspace_path(workspace), params: { workspace: { name: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "authorization" do
      it "denies non-owner from updating workspace" do
        workspace = create(:workspace)
        sign_in_member_of(workspace)
        patch workspace_path(workspace), params: { workspace: { name: "Hacked" } }
        expect(response).to have_http_status(:redirect)
        expect(workspace.reload.name).not_to eq("Hacked")
      end

      it "denies non-owner from destroying workspace" do
        workspace = create(:workspace)
        sign_in_member_of(workspace)
        delete workspace_path(workspace)
        expect(workspace.reload).not_to be_discarded
      end
    end
  end
end
