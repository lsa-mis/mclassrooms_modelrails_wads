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

    # Test-data builder (let-diet worked example, #440): the target-member
    # pair below used to be declared as paired let!s in six separate contexts
    # — duplication masquerading as shared state, and the file grew 38→48
    # lets in a month. One named builder keeps each example's cast visible at
    # its call site; a context keeps a `let` only when several of its own
    # examples share the record. Convention: /docs/developer/getting-started ("Spec conventions").
    def add_member(role: nil, user: create(:user), to: workspace)
      create(:membership, *[ role ].compact, user: user, workspace: to)
    end

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
        let!(:alice_membership) { add_member(user: create(:user, first_name: "Alice", last_name: "Anderson")) }

        it "filters by search query" do
          get workspace_members_path(workspace, q: "Alice")
          expect(response.body).to include("Alice")
        end

        it "excludes non-matching members" do
          get workspace_members_path(workspace, q: "Zzzzz")
          # Scope to the members table — chrome surfaces (e.g. the
          # notifications-bell dropdown) may legitimately surface "Alice"
          # when the workspace-member-added notifier mentions her.
          doc = Nokogiri::HTML(response.body)
          members_frame = doc.at_css("turbo-frame#members_results").to_s
          expect(members_frame).not_to include("Alice")
        end
      end

      context "with role filter" do
        let!(:admin_membership) { add_member(role: :admin, user: create(:user, first_name: "AdminUser", last_name: "Test")) }

        it "filters by role" do
          get workspace_members_path(workspace, role: "admin")
          doc = Nokogiri::HTML(response.body)
          members_frame = doc.at_css("turbo-frame#members_results").to_s
          expect(members_frame).to include("AdminUser")
          expect(members_frame).not_to include(CGI.escapeHTML(user.full_name))
        end
      end

      context "with status filter" do
        let!(:deactivated_user) { create(:user, first_name: "Deactivated", last_name: "User") }
        let!(:deactivated_membership) { add_member(user: deactivated_user) }

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

        # #124: the sort headers render over the COMBINED table, so invitation
        # rows must honor them too — previously the invitation scope accepted
        # no sort at all and a user clicking "Email ↑" got half a sorted list
        # with no signal.
        it "applies the email sort to invitation rows, not just memberships" do
          create(:invitation, invitable: workspace, email: "zzz@example.com")
          create(:invitation, invitable: workspace, email: "aaa@example.com")

          get workspace_members_path(workspace, sort: "email", direction: "asc")

          doc = Nokogiri::HTML(response.body)
          emails = doc.css("tr").map(&:text).select { |t| t.match?(/@example\.com/) }
          aaa = emails.index { |t| t.include?("aaa@example.com") }
          zzz = emails.index { |t| t.include?("zzz@example.com") }
          expect(aaa).to be < zzz,
            "invitation rows must order by the active email sort (asc): got aaa at #{aaa}, zzz at #{zzz}"
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

        # #125: mixed-row boundary — invitations render before memberships, so
        # with 3 invitations + 23 members (26 rows, 25-per-page), page 2 must
        # hold exactly the overflow membership row, and the pagy count must be
        # the combined total.
        it "paginates the combined invitation+membership list across the boundary" do
          3.times { |i| create(:invitation, invitable: workspace, email: "invite-#{i}@example.com") }

          get workspace_members_path(workspace)
          first_page = Nokogiri::HTML(response.body)
          expect(first_page.css("tr").map(&:text).join).to include("invite-0@example.com")

          get workspace_members_path(workspace, page: 2)
          expect(response).to have_http_status(:ok)
          second_page = Nokogiri::HTML(response.body)
          expect(second_page.css("tr").map(&:text).join).not_to include("invite-0@example.com"),
            "invitations sort to the front of the combined list; page 2 should hold only overflow membership rows"
        end

        # #125: filters must compose with pagination. A beyond-range page
        # (stale bookmark, or a filter narrowing the set) serves the LAST
        # real page of the filtered results — this spec originally asserted
        # "no 500" and promptly caught one: Pagy 43 hands the view nil rows
        # for an out-of-range request, so the controller clamps.
        it "clamps a beyond-range page to the last page of the filtered set" do
          create(:invitation, invitable: workspace, email: "filtered-target@example.com")

          get workspace_members_path(workspace, q: "filtered-target", page: 7)
          expect(response).to have_http_status(:ok)
          expect(Nokogiri::HTML(response.body).css("tr").map(&:text).join).to include("filtered-target@example.com"),
            "a beyond-range page must clamp to the last real page, not 500 or render a phantom empty page"
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

        it "shows pending invitations interleaved in the members table" do
          get workspace_members_path(workspace)
          # The pending invitation row is rendered inline in the unified
          # members tbody — its email and "Pending" status badge are present.
          expect(response.body).to include("newperson@example.com")
          expect(response.body).to include(I18n.t("workspaces.members.index.pending_invitations.pending"))
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
      it "renders the role change form" do
        target_membership = add_member
        get edit_workspace_member_path(workspace, target_membership)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /workspaces/:workspace_slug/members/:id" do
      let!(:target_membership) { add_member }
      let(:admin_role) { Role.system_default!("admin") }

      it "changes the member's role" do
        patch workspace_member_path(workspace, target_membership), params: { membership: { role_id: admin_role.id } }
        expect(target_membership.reload.role).to eq(admin_role)
      end

      it "redirects to members list" do
        patch workspace_member_path(workspace, target_membership), params: { membership: { role_id: admin_role.id } }
        expect(response).to redirect_to(workspace_members_path(workspace))
      end
    end

    # SEC-1: an Admin (manage_members, not manage_workspace) must not be able
    # to grant the Owner role — to anyone, including themselves — nor demote an
    # Owner. The persisted role staying unchanged is the load-bearing assertion.
    describe "PATCH .../members/:id — privilege escalation" do
      let(:owner_role)  { Role.system_default!("owner") }
      let(:admin_role)  { Role.system_default!("admin") }
      let(:member_role) { Role.system_default!("member") }
      let(:admin_user)  { create(:user) }
      let!(:admin_membership) { create(:membership, :admin, user: admin_user, workspace: workspace) }

      before { sign_in(admin_user) }

      it "refuses an admin promoting another member to owner and leaves the role unchanged" do
        target = create(:membership, user: create(:user), workspace: workspace)
        patch workspace_member_path(workspace, target), params: { membership: { role_id: owner_role.id } }
        expect(target.reload.role).to eq(member_role)
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to be_present
      end

      it "refuses an admin promoting their OWN membership to owner" do
        patch workspace_member_path(workspace, admin_membership), params: { membership: { role_id: owner_role.id } }
        expect(admin_membership.reload.role).to eq(admin_role)
        expect(response).to have_http_status(:redirect)
      end

      # G (SEC-1 follow-up): a blocked escalation attempt is itself a security
      # event. The refusal must reach the admin activity feed, not just 403.
      it "logs the blocked escalation to the admin activity feed" do
        expect {
          patch workspace_member_path(workspace, admin_membership), params: { membership: { role_id: owner_role.id } }
        }.to change { ActivityLog.where(action: "membership.role_grant_blocked").count }.by(1)

        entry = ActivityLog.where(action: "membership.role_grant_blocked").last
        expect(entry.visibility).to eq("admin")
        expect(entry.actor).to eq(admin_user)
        expect(entry.metadata["attempted_role"]).to eq("owner")
      end

      it "refuses an admin editing an owner's membership at all" do
        patch workspace_member_path(workspace, membership), params: { membership: { role_id: admin_role.id } }
        expect(membership.reload.role).to eq(owner_role)
        expect(response).to have_http_status(:redirect)
      end

      it "does not offer the Owner option in an admin's edit dropdown" do
        target = create(:membership, user: create(:user), workspace: workspace)
        get edit_workspace_member_path(workspace, target)
        select = Nokogiri::HTML(response.body).at_css("select[name='membership[role_id]']")
        expect(select.to_s).not_to include("Owner")
      end

      it "still lets an admin assign a non-privileged role" do
        target = create(:membership, user: create(:user), workspace: workspace)
        patch workspace_member_path(workspace, target), params: { membership: { role_id: admin_role.id } }
        expect(target.reload.role).to eq(admin_role)
      end

      it "refuses an admin reactivating a deactivated owner and leaves it discarded" do
        deactivated_owner = create(:membership, :owner, user: create(:user), workspace: workspace)
        deactivated_owner.discard!
        patch reactivate_workspace_member_path(workspace, deactivated_owner)
        expect(deactivated_owner.reload).to be_discarded
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "PATCH .../members/:id — viewer actor" do
      let(:member_role) { Role.system_default!("member") }
      let(:viewer_user) { create(:user) }
      let!(:viewer_membership) do
        create(:membership, user: viewer_user, workspace: workspace, role: Role.system_default!("viewer"))
      end

      before { sign_in(viewer_user) }

      it "denies a viewer changing anyone's role and leaves it unchanged" do
        target = create(:membership, user: create(:user), workspace: workspace)
        original = target.role
        patch workspace_member_path(workspace, target), params: { membership: { role_id: member_role.id } }
        expect(target.reload.role).to eq(original)
        expect(response).to have_http_status(:redirect)
      end
    end

    # SEC-1 (adjacent): a workspace must always retain at least one owner.
    describe "PATCH .../members/:id — owner floor" do
      let(:admin_role) { Role.system_default!("admin") }
      let(:owner_role) { Role.system_default!("owner") }

      it "refuses to demote the sole owner and leaves them owner" do
        # `user`/`membership` (outer let) is the only owner; signed in as them.
        patch workspace_member_path(workspace, membership), params: { membership: { role_id: admin_role.id } }
        expect(membership.reload.role).to eq(owner_role)
        expect(response).to redirect_to(workspace_members_path(workspace))
        expect(flash[:alert]).to eq(I18n.t("workspaces.members.update.cannot_demote_last_owner"))
      end

      it "allows demoting an owner when another owner remains" do
        second_owner = create(:membership, :owner, user: create(:user), workspace: workspace)
        patch workspace_member_path(workspace, second_owner), params: { membership: { role_id: admin_role.id } }
        expect(second_owner.reload.role).to eq(admin_role)
      end
    end

    # C7: the last-owner rescues name their condition (Membership::LastOwner).
    # Any OTHER validation failure on these paths is a different bug and must
    # surface as itself, not be blanket-mapped to the last-owner flash.
    describe "unrelated validation failures are not reported as last-owner" do
      let(:admin_role) { Role.system_default!("admin") }

      it "PATCH surfaces a non-last-owner RecordInvalid instead of the demote flash" do
        target = add_member
        allow_any_instance_of(Membership).to receive(:change_role!)
          .and_raise(ActiveRecord::RecordInvalid.new(target))
        patch workspace_member_path(workspace, target), params: { membership: { role_id: admin_role.id } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to be_nil
      end

      it "DELETE surfaces a non-last-owner RecordInvalid instead of the deactivate flash" do
        target = add_member
        allow_any_instance_of(Membership).to receive(:deactivate!)
          .and_raise(ActiveRecord::RecordInvalid.new(target))
        delete workspace_member_path(workspace, target)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to be_nil
      end
    end

    describe "DELETE /workspaces/:workspace_slug/members/:id" do
      let!(:target_membership) { add_member }

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
      let!(:target_membership) { add_member }

      before { target_membership.discard! }

      it "reactivates the member" do
        patch reactivate_workspace_member_path(workspace, target_membership)
        expect(target_membership.reload).not_to be_discarded
      end
    end

    describe "PATCH /workspaces/:workspace_slug/members/:id/transfer_ownership" do
      it "transfers ownership" do
        target_membership = add_member
        owner_role = Role.system_default!("owner")
        admin_role = Role.system_default!("admin")
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
      let!(:target_membership) { add_member }

      before do
        add_member(user: regular_member)
        sign_in(regular_member)
      end

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

RSpec.describe "Workspaces::Members destroy", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }

  before { sign_in(user) }

  describe "DELETE /workspaces/:slug/members/:id" do
    context "user leaving their own (non-personal) membership" do
      let!(:user_membership) { create(:membership, user: user, workspace: workspace) }
      let!(:owner_membership) { create(:membership, :owner, user: other_user, workspace: workspace) }

      it "deactivates the membership and redirects to /workspaces with the 'left' flash" do
        delete workspace_member_path(workspace, user_membership)
        expect(response).to redirect_to(workspaces_path)
        follow_redirect!
        expect(flash[:notice]).to eq(I18n.t("workspaces.members.destroy.left", workspace: workspace.name))
        expect(user_membership.reload.discarded_at).to be_present
      end
    end

    context "user trying to leave their personal workspace" do
      let!(:personal_membership) { create(:membership, :owner, user: user, workspace: workspace) }
      before { user.update!(personal_workspace_id: workspace.id) }

      it "is forbidden by the policy" do
        delete workspace_member_path(workspace, personal_membership)
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
        expect(personal_membership.reload.discarded_at).to be_nil
      end
    end

    context "user trying to leave as the last owner" do
      let!(:user_owner_membership) { create(:membership, :owner, user: user, workspace: workspace) }
      # No other owners exist.

      it "is forbidden and the membership remains kept" do
        delete workspace_member_path(workspace, user_owner_membership)
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
        expect(user_owner_membership.reload.discarded_at).to be_nil
      end
    end

    context "admin deactivating another member (existing case)" do
      let!(:admin_membership) { create(:membership, :admin, user: user, workspace: workspace) }
      let!(:other_membership) { create(:membership, user: other_user, workspace: workspace) }
      let!(:other_owner) { create(:membership, :owner, user: create(:user), workspace: workspace) }

      it "deactivates and redirects to the members table (unchanged behavior)" do
        delete workspace_member_path(workspace, other_membership)
        expect(response).to redirect_to(workspace_members_path(workspace))
        follow_redirect!
        expect(flash[:notice]).to eq(I18n.t("workspaces.members.destroy.deactivated"))
        expect(other_membership.reload.discarded_at).to be_present
      end
    end

    context "non-member tries to delete someone else's membership" do
      let!(:stranger) { user }  # the signed-in user has no membership in workspace
      let!(:target_membership) { create(:membership, user: other_user, workspace: workspace) }

      it "is forbidden" do
        delete workspace_member_path(workspace, target_membership)
        expect(response).to have_http_status(:redirect)  # set_workspace redirects to /workspaces on RecordNotFound
      end
    end
  end
end
