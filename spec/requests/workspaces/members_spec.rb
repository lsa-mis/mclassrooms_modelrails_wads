require "rails_helper"

RSpec.describe "Workspace Members", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/members to sign in" do
      get workspace_members_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }
    let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

    before { sign_in(user) }

    describe "GET /workspaces/:workspace_slug/members" do
      it "lists workspace members" do
        get workspace_members_path(workspace)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(CGI.escapeHTML(user.full_name))
      end

      it "shows member roles" do
        get workspace_members_path(workspace)
        expect(response.body).to include("Owner")
      end

      context "with search" do
        let!(:alice) { create(:user, first_name: "Alice", last_name: "Anderson") }
        let!(:alice_membership) { create(:membership, user: alice, workspace: workspace) }

        it "filters by search query" do
          get workspace_members_path(workspace, q: "Alice")
          expect(response.body).to include("Alice")
        end

        it "excludes non-matching members" do
          get workspace_members_path(workspace, q: "Zzzzz")
          expect(response.body).not_to include("Alice")
        end
      end

      context "with role filter" do
        let!(:admin_user) { create(:user, first_name: "AdminUser", last_name: "Test") }
        let!(:admin_membership) { create(:membership, :admin, user: admin_user, workspace: workspace) }

        it "filters by role" do
          get workspace_members_path(workspace, role: "admin")
          expect(response.body).to include("AdminUser")
          expect(response.body).not_to include(CGI.escapeHTML(user.full_name))
        end
      end

      context "with status filter" do
        let!(:deactivated_user) { create(:user, first_name: "Deactivated", last_name: "User") }
        let!(:deactivated_membership) { create(:membership, user: deactivated_user, workspace: workspace) }

        before { deactivated_membership.discard! }

        it "filters active members" do
          get workspace_members_path(workspace, status: "active")
          expect(response.body).to include(CGI.escapeHTML(user.full_name))
          expect(response.body).not_to include(CGI.escapeHTML(deactivated_user.full_name))
        end

        it "filters deactivated members" do
          get workspace_members_path(workspace, status: "deactivated")
          expect(response.body).to include("Deactivated")
        end
      end

      context "with sorting" do
        it "sorts by name ascending" do
          get workspace_members_path(workspace, sort: "name", direction: "asc")
          expect(response).to have_http_status(:ok)
        end

        it "sorts by role" do
          get workspace_members_path(workspace, sort: "role", direction: "desc")
          expect(response).to have_http_status(:ok)
        end
      end

      context "with pagination" do
        before do
          workspace.update!(max_members: 50)
          22.times { create(:membership, workspace: workspace) }
        end

        it "paginates results" do
          get workspace_members_path(workspace)
          expect(response.body).to include("members_results")
        end

        it "respects page parameter" do
          get workspace_members_path(workspace, page: 2)
          expect(response).to have_http_status(:ok)
        end
      end

      context "with Turbo Frame request" do
        it "responds to Turbo Frame requests" do
          get workspace_members_path(workspace),
              headers: { "Turbo-Frame" => "members_results" }
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("members_results")
        end
      end

      context "with empty results" do
        it "shows empty state when search matches nothing" do
          get workspace_members_path(workspace, q: "nonexistent_person_xyz")
          expect(response.body).to include(I18n.t("workspaces.members.index.empty"))
        end
      end

      context "invite button" do
        it "shows invite button for users with manage_members permission" do
          get workspace_members_path(workspace)
          expect(response.body).to include(I18n.t("workspaces.members.index.invite_member"))
        end

        it "hides invite button for regular members" do
          regular = create(:user)
          create(:membership, user: regular, workspace: workspace)
          sign_in(regular)
          get workspace_members_path(workspace)
          expect(response.body).not_to include(I18n.t("workspaces.members.index.invite_member"))
        end
      end

      context "pending invitations" do
        let!(:pending_invitation) do
          create(:invitation, invitable: workspace, email: "newperson@example.com",
                 invited_by: user)
        end

        it "shows pending invitations on members page" do
          get workspace_members_path(workspace)
          expect(response.body).to include("newperson@example.com")
          expect(response.body).to include(I18n.t("workspaces.members.index.pending_invitations.title"))
        end

        it "shows magic link label for magic link invitations" do
          create(:invitation, :magic_link, invitable: workspace, invited_by: user)
          get workspace_members_path(workspace)
          expect(response.body).to include(I18n.t("workspaces.members.index.pending_invitations.magic_link"))
        end

        it "shows pending badge" do
          get workspace_members_path(workspace)
          expect(response.body).to include(I18n.t("workspaces.members.index.pending_invitations.pending"))
        end

        it "shows resend and revoke buttons for authorized users" do
          get workspace_members_path(workspace)
          expect(response.body).to include(I18n.t("workspaces.members.index.pending_invitations.resend"))
          expect(response.body).to include(I18n.t("workspaces.members.index.pending_invitations.revoke"))
        end

        it "hides resend and revoke for regular members" do
          regular = create(:user)
          create(:membership, user: regular, workspace: workspace)
          sign_in(regular)
          get workspace_members_path(workspace)
          expect(response.body).not_to include(I18n.t("workspaces.members.index.pending_invitations.resend"))
        end

        it "excludes accepted invitations" do
          pending_invitation.update!(status: "accepted", accepted_at: Time.current)
          get workspace_members_path(workspace)
          expect(response.body).not_to include("newperson@example.com")
        end

        it "excludes expired invitations" do
          pending_invitation.update!(expires_at: 1.day.ago)
          get workspace_members_path(workspace)
          expect(response.body).not_to include("newperson@example.com")
        end

        it "excludes revoked invitations" do
          pending_invitation.revoke!
          get workspace_members_path(workspace)
          expect(response.body).not_to include("newperson@example.com")
        end
      end
    end

    describe "GET /workspaces/:workspace_slug/members/:id/edit" do
      let(:target) { create(:user) }
      let!(:target_membership) { create(:membership, user: target, workspace: workspace) }

      it "renders the role change form" do
        get edit_workspace_member_path(workspace, target_membership)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /workspaces/:workspace_slug/members/:id" do
      let(:target) { create(:user) }
      let!(:target_membership) { create(:membership, user: target, workspace: workspace) }
      let(:admin_role) { Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" } }

      it "changes the member's role" do
        patch workspace_member_path(workspace, target_membership), params: { membership: { role_id: admin_role.id } }
        expect(target_membership.reload.role).to eq(admin_role)
      end

      it "redirects to members list" do
        patch workspace_member_path(workspace, target_membership), params: { membership: { role_id: admin_role.id } }
        expect(response).to redirect_to(workspace_members_path(workspace))
      end
    end

    describe "DELETE /workspaces/:workspace_slug/members/:id" do
      let(:target) { create(:user) }
      let!(:target_membership) { create(:membership, user: target, workspace: workspace) }

      it "deactivates the member" do
        delete workspace_member_path(workspace, target_membership)
        expect(target_membership.reload).to be_discarded
      end

      it "redirects to members list" do
        delete workspace_member_path(workspace, target_membership)
        expect(response).to redirect_to(workspace_members_path(workspace))
      end
    end

    describe "PATCH /workspaces/:workspace_slug/members/:id/reactivate" do
      let(:target) { create(:user) }
      let!(:target_membership) { create(:membership, user: target, workspace: workspace) }

      before { target_membership.discard! }

      it "reactivates the member" do
        patch reactivate_workspace_member_path(workspace, target_membership)
        expect(target_membership.reload).not_to be_discarded
      end
    end

    describe "PATCH /workspaces/:workspace_slug/members/:id/transfer_ownership" do
      let(:target) { create(:user) }
      let!(:target_membership) { create(:membership, user: target, workspace: workspace) }

      it "transfers ownership" do
        owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
        admin_role = Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" }
        patch transfer_ownership_workspace_member_path(workspace, target_membership)
        expect(target_membership.reload.role).to eq(owner_role)
        expect(membership.reload.role).to eq(admin_role)
      end
    end

    describe "member authorization" do
      let(:member_user) { create(:user) }
      before { create(:membership, user: member_user, workspace: workspace) }

      it "denies role change for regular members" do
        target = create(:membership, workspace: workspace)
        sign_in(member_user)
        patch workspace_member_path(workspace, target), params: { membership: { role_id: membership.role_id } }
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "DELETE last owner" do
      it "returns redirect with alert when deactivating last owner" do
        # user is owner (outer let). Create an admin user who can manage_members but is not owner.
        admin_user = create(:user)
        create(:membership, :admin, user: admin_user, workspace: workspace)
        sign_in(admin_user)
        # user's membership is the last (only) owner - trying to delete it should fail with alert
        delete workspace_member_path(workspace, membership)
        expect(response).to redirect_to(workspace_members_path(workspace))
        expect(flash[:alert]).to be_present
      end
    end

    describe "member authorization" do
      let(:regular_member) { create(:user) }
      let!(:regular_membership) { create(:membership, user: regular_member, workspace: workspace) }
      let(:target) { create(:user) }
      let!(:target_membership) { create(:membership, user: target, workspace: workspace) }

      before { sign_in(regular_member) }

      it "denies edit" do
        get edit_workspace_member_path(workspace, target_membership)
        expect(response).to have_http_status(:redirect)
      end

      it "denies reactivate" do
        target_membership.discard!
        patch reactivate_workspace_member_path(workspace, target_membership)
        expect(target_membership.reload).to be_discarded
      end

      it "denies transfer_ownership" do
        patch transfer_ownership_workspace_member_path(workspace, target_membership)
        expect(response).to have_http_status(:redirect)
      end
    end
  end
end
