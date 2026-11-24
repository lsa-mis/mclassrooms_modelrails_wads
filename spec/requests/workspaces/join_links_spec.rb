require "rails_helper"

RSpec.describe "Workspaces::JoinLinks", type: :request do
  def team_workspace = create(:workspace, personal: false)

  def owner_of(workspace) = create(:membership, :owner, workspace: workspace).user

  def member_of(workspace) = create(:membership, workspace: workspace).user

  describe "POST /workspaces/:slug/join_links" do
    context "as an admin/owner" do
      it "creates a new active join link" do
        workspace = team_workspace
        sign_in_as_owner_of(workspace)
        member_of(workspace)

        expect {
          post workspace_join_links_path(workspace)
        }.to change(workspace.join_links.active, :count).by(1)

        expect(response).to redirect_to(edit_workspace_settings_path(workspace))
        expect(flash[:notice]).to eq(I18n.t("workspaces.join_links.create.rotated"))
      end

      it "atomically rotates — revokes any existing active link and creates a new one" do
        workspace = team_workspace
        owner = sign_in_as_owner_of(workspace)
        member_of(workspace)
        existing = create(:workspace_join_link, workspace: workspace, created_by: owner)
        original_digest = existing.token_digest

        post workspace_join_links_path(workspace)

        expect(existing.reload).to be_revoked
        expect(workspace.join_links.active.count).to eq(1)
        expect(workspace.join_links.active.first.token_digest).not_to eq(original_digest)
      end

      # Expired-but-unrevoked is still `current` (partial unique index), so
      # rotation must revoke it first or create! collides (#952).
      it "rotates an expired current link without colliding, leaving exactly one current, active link" do
        workspace = team_workspace
        owner = sign_in_as_owner_of(workspace)
        member_of(workspace)
        expired = create(:workspace_join_link, workspace: workspace, created_by: owner)
        travel_to 8.days.from_now do
          expect(expired).to be_expired
          expect { post workspace_join_links_path(workspace) }.not_to raise_error

          expect(expired.reload).to be_revoked
          expect(workspace.join_links.current.count).to eq(1)
          expect(workspace.join_links.active.count).to eq(1)
        end
      end

      describe "show-once reveal (the token is hashed at rest)" do
        it "reveals the full join URL exactly once after generating, then masks it" do
          permit_open_join_links
          workspace = team_workspace
          sign_in_as_owner_of(workspace)
          member_of(workspace)
          workspace.update!(join_policy: "open_link")

          post workspace_join_links_path(workspace)
          follow_redirect!

          link = workspace.join_links.active.first
          expect(response.body).to include(I18n.t("workspaces.settings.join_policy.show_once_warning_lead"))

          # The revealed plaintext exists only in this one response; prove it
          # matches the digest stored at rest (never re-derivable from the DB).
          revealed = response.body[%r{/workspaces/#{workspace.slug}/joins/([A-Za-z0-9_-]+)}, 1]
          expect(revealed).to be_present
          expect(WorkspaceJoinLink.digest(revealed)).to eq(link.token_digest)

          # A fresh visit no longer exposes the URL — masked steady state only.
          get edit_workspace_settings_path(workspace)
          expect(response.body).not_to include(I18n.t("workspaces.settings.join_policy.show_once_warning_lead"))
          expect(response.body).to include(I18n.t("workspaces.settings.join_policy.masked_help"))
          expect(response.body).to include(link.masked_token)
        end
      end
    end

    context "as a regular member" do
      it "rejects with not-authorized (no link created)" do
        workspace = team_workspace
        owner_of(workspace)
        sign_in(member_of(workspace))

        expect {
          post workspace_join_links_path(workspace)
        }.not_to change(workspace.join_links, :count)
      end
    end
  end

  describe "DELETE /workspaces/:slug/join_links/:id" do
    context "as an admin/owner" do
      it "revokes (soft-removes) the link" do
        workspace = team_workspace
        owner = owner_of(workspace)
        member_of(workspace)
        link = create(:workspace_join_link, workspace: workspace, created_by: owner)
        sign_in(owner)

        delete workspace_join_link_path(workspace, link)
        expect(link.reload).to be_revoked
        expect(response).to redirect_to(edit_workspace_settings_path(workspace))
        expect(flash[:notice]).to eq(I18n.t("workspaces.join_links.destroy.revoked"))
      end
    end

    context "as a regular member" do
      it "rejects with not-authorized (link stays active)" do
        workspace = team_workspace
        owner = owner_of(workspace)
        link = create(:workspace_join_link, workspace: workspace, created_by: owner)
        sign_in(member_of(workspace))

        delete workspace_join_link_path(workspace, link)
        expect(link.reload).not_to be_revoked
      end
    end

    context "cross-workspace IDOR" do
      it "does not let an owner delete another workspace's link via the wrong slug" do
        workspace = team_workspace
        owner = owner_of(workspace)
        member_of(workspace)
        create(:workspace_join_link, workspace: workspace, created_by: owner)
        other_workspace = team_workspace
        other_link = create(:workspace_join_link, workspace: other_workspace, created_by: owner)
        sign_in(owner)

        delete workspace_join_link_path(workspace, other_link)
        # 404 or redirect, the other workspace's link must stay active:
        # that is the IDOR assertion.
        expect(other_link.reload).not_to be_revoked
      end
    end
  end
end
