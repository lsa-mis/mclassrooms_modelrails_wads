require "rails_helper"

RSpec.describe "Workspaces::JoinLinks", type: :request do
  let(:workspace) { create(:workspace, personal: false) }
  let(:owner) { create(:user) }
  let(:member) { create(:user) }
  let!(:owner_role) {
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    }
  }
  let!(:member_role) {
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
      r.name = "Member"
      r.permissions = { manage_projects: true }
    }
  }

  before do
    workspace.memberships.create!(user: owner, role: owner_role)
    workspace.memberships.create!(user: member, role: member_role)
  end

  describe "POST /workspaces/:slug/join_links" do
    context "as an admin/owner" do
      before { sign_in(owner) }

      it "creates a new active join link" do
        expect {
          post workspace_join_links_path(workspace)
        }.to change(workspace.join_links.active, :count).by(1)
      end

      it "atomically rotates — revokes any existing active link and creates a new one" do
        existing = create(:workspace_join_link, workspace: workspace, created_by: owner)
        original_token = existing.token

        post workspace_join_links_path(workspace)

        expect(existing.reload).to be_revoked
        expect(workspace.join_links.active.count).to eq(1)
        expect(workspace.join_links.active.first.token).not_to eq(original_token)
      end
    end

    context "as a regular member" do
      before { sign_in(member) }

      it "rejects with not-authorized (no link created)" do
        expect {
          post workspace_join_links_path(workspace)
        }.not_to change(workspace.join_links, :count)
      end
    end
  end

  describe "DELETE /workspaces/:slug/join_links/:id" do
    let!(:link) { create(:workspace_join_link, workspace: workspace, created_by: owner) }

    context "as an admin/owner" do
      before { sign_in(owner) }

      it "revokes (soft-removes) the link" do
        delete workspace_join_link_path(workspace, link)
        expect(link.reload).to be_revoked
      end
    end

    context "as a regular member" do
      before { sign_in(member) }

      it "rejects with not-authorized (link stays active)" do
        delete workspace_join_link_path(workspace, link)
        expect(link.reload).not_to be_revoked
      end
    end

    context "cross-workspace IDOR" do
      let(:other_workspace) { create(:workspace, personal: false) }
      let!(:other_link) { create(:workspace_join_link, workspace: other_workspace, created_by: owner) }

      before { sign_in(owner) }

      it "does not let an owner delete another workspace's link via the wrong slug" do
        delete workspace_join_link_path(workspace, other_link)
        # Whether the request 404s or redirects with an error, the other
        # workspace's link must remain active — that's the load-bearing
        # IDOR-protection assertion. ApplicationController rescues
        # RecordNotFound globally and redirects.
        expect(other_link.reload).not_to be_revoked
      end
    end
  end
end
