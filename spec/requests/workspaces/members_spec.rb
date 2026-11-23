require "rails_helper"

RSpec.describe "Workspace Members", type: :request do
  def sign_in_as(membership)
    sign_in(membership.user)
    membership
  end

  def signed_in_owner
    sign_in_as(create(:membership, :owner))
  end

  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/members to sign in" do
      get workspace_members_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /workspaces/:workspace_slug/members" do
    it "lists workspace members" do
      owner = signed_in_owner
      get workspace_members_path(owner.workspace)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(owner.user.full_name))
    end

    it "shows member roles" do
      get workspace_members_path(signed_in_owner.workspace)
      expect(response.body).to include("Owner")
    end

    # #764: the buttons rotor reads action buttons out of row context, so each
    # name carries its subject or every row announces "Deactivate" alike.
    it "gives every per-row action button an accessible name carrying its subject, no two alike" do
      owner = signed_in_owner
      workspace = owner.workspace
      alice = add_member(workspace, user: create(:user, first_name: "Alice", last_name: "Ames"))
      bob = add_member(workspace, user: create(:user, first_name: "Bob", last_name: "Berg"))
      invitation = create(:invitation, invitable: workspace, email: "carol@example.com", invited_by: owner.user)

      get workspace_members_path(workspace)
      page = Capybara.string(response.body)

      [ alice.user.full_name, bob.user.full_name ].each do |name|
        expect(page).to have_css("[aria-label*='#{name}']", minimum: 1)
      end
      expect(page).to have_css("[aria-label*='#{invitation.email}']", minimum: 2) # resend + revoke

      labels = page.all("button[aria-label], a[aria-label]", visible: :all)
        .map { |el| el["aria-label"] }
        .select { |l| l.include?(alice.user.full_name) || l.include?(bob.user.full_name) || l.include?(invitation.email) }
      expect(labels.size).to eq(labels.uniq.size), "duplicate accessible names: #{labels.tally.select { |_, c| c > 1 }.keys.inspect}"
    end

    it "renders member and invitation status pills through UI::Badge (canonical chip look)" do
      owner = signed_in_owner
      workspace = owner.workspace
      add_member(workspace).update!(discarded_at: Time.current)
      create(:invitation, invitable: workspace, email: "pillcheck@example.com", invited_by: owner.user)

      get workspace_members_path(workspace)

      html = Capybara.string(response.body)
      expect(html).to have_css("span[data-variant='soft'][data-tone='success']",
        exact_text: I18n.t("workspaces.members.index.active"))
      expect(html).to have_css("span[data-variant='soft'][data-tone='danger']",
        exact_text: I18n.t("workspaces.members.index.deactivated"))
      expect(html).to have_css("span[data-variant='soft'][data-tone='warning']",
        exact_text: I18n.t("workspaces.members.index.pending_invitations.pending"))
    end

    context "with search" do
      it "filters by search query" do
        workspace = signed_in_owner.workspace
        add_member(workspace, user: create(:user, first_name: "Alice", last_name: "Anderson"))

        get workspace_members_path(workspace, q: "Alice")
        expect(response.body).to include("Alice")
      end

      it "excludes non-matching members" do
        workspace = signed_in_owner.workspace
        add_member(workspace, user: create(:user, first_name: "Alice", last_name: "Anderson"))

        get workspace_members_path(workspace, q: "Zzzzz")
        # Scoped to the members table: the notifications bell may mention Alice.
        members_frame = Nokogiri::HTML(response.body).at_css("turbo-frame#members_results").to_s
        expect(members_frame).not_to include("Alice")
      end
    end

    context "with role filter" do
      it "filters by role" do
        owner = signed_in_owner
        add_member(owner.workspace, role: :admin, user: create(:user, first_name: "AdminUser", last_name: "Test"))

        get workspace_members_path(owner.workspace, role: "admin")
        members_frame = Nokogiri::HTML(response.body).at_css("turbo-frame#members_results").to_s
        expect(members_frame).to include("AdminUser")
        expect(members_frame).not_to include(CGI.escapeHTML(owner.user.full_name))
      end
    end

    context "with status filter" do
      def add_deactivated_member(workspace)
        add_member(workspace, user: create(:user, first_name: "Deactivated", last_name: "User")).tap do |membership|
          membership.update!(discarded_at: Time.current)
        end
      end

      it "filters active members" do
        owner = signed_in_owner
        deactivated = add_deactivated_member(owner.workspace)

        get workspace_members_path(owner.workspace, status: "active")
        expect(response.body).to include(CGI.escapeHTML(owner.user.full_name))
        expect(response.body).not_to include(CGI.escapeHTML(deactivated.user.full_name))
      end

      it "filters deactivated members" do
        workspace = signed_in_owner.workspace
        add_deactivated_member(workspace)

        get workspace_members_path(workspace, status: "deactivated")
        expect(response.body).to include("Deactivated")
      end
    end

    context "with sorting" do
      it "sorts by name ascending" do
        get workspace_members_path(signed_in_owner.workspace, sort: "name", direction: "asc")
        expect(response).to have_http_status(:ok)
      end

      it "sorts by role" do
        get workspace_members_path(signed_in_owner.workspace, sort: "role", direction: "desc")
        expect(response).to have_http_status(:ok)
      end

      # #124: the sort headers span the combined table, so invitation rows
      # honor them too, not just memberships.
      it "applies the email sort to invitation rows, not just memberships" do
        workspace = signed_in_owner.workspace
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
      def workspace_with_23_members
        signed_in_owner.workspace.tap do |workspace|
          workspace.update!(max_members: 50)
          22.times { create(:membership, workspace: workspace) }
        end
      end

      it "paginates results" do
        get workspace_members_path(workspace_with_23_members)
        expect(response.body).to include("members_results")
      end

      it "respects page parameter" do
        get workspace_members_path(workspace_with_23_members, page: 2)
        expect(response).to have_http_status(:ok)
      end

      # #125: invitations render first, so with 3 invitations and 23 members
      # (25 a page) page 2 holds only the overflow membership row.
      it "paginates the combined invitation+membership list across the boundary" do
        workspace = workspace_with_23_members
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

      # #125: a beyond-range page serves the last real page of the filtered
      # set; Pagy hands the view nil rows for it, so the controller clamps.
      it "clamps a beyond-range page to the last page of the filtered set" do
        workspace = workspace_with_23_members
        create(:invitation, invitable: workspace, email: "filtered-target@example.com")

        get workspace_members_path(workspace, q: "filtered-target", page: 7)
        expect(response).to have_http_status(:ok)
        expect(Nokogiri::HTML(response.body).css("tr").map(&:text).join).to include("filtered-target@example.com"),
          "a beyond-range page must clamp to the last real page, not 500 or render a phantom empty page"
      end
    end

    context "with Turbo Frame request" do
      it "responds to Turbo Frame requests" do
        get workspace_members_path(signed_in_owner.workspace),
            headers: { "Turbo-Frame" => "members_results" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("members_results")
      end
    end

    context "with empty results" do
      it "shows empty state when search matches nothing" do
        get workspace_members_path(signed_in_owner.workspace, q: "nonexistent_person_xyz")
        expect(response.body).to include(I18n.t("workspaces.members.index.empty"))
      end
    end

    context "invite button" do
      it "shows invite button for users with manage_members permission" do
        get workspace_members_path(signed_in_owner.workspace)
        expect(response.body).to include(I18n.t("workspaces.members.index.invite_member"))
      end

      it "hides invite button for regular members" do
        workspace = create(:membership, :owner).workspace
        sign_in_as(add_member(workspace))

        get workspace_members_path(workspace)
        expect(response.body).not_to include(I18n.t("workspaces.members.index.invite_member"))
      end
    end

    context "pending invitations" do
      def invite_newperson(owner)
        create(:invitation, invitable: owner.workspace, email: "newperson@example.com", invited_by: owner.user)
      end

      it "shows pending invitations interleaved in the members table" do
        owner = signed_in_owner
        invite_newperson(owner)

        get workspace_members_path(owner.workspace)
        expect(response.body).to include("newperson@example.com")
        expect(response.body).to include(I18n.t("workspaces.members.index.pending_invitations.pending"))
      end

      it "shows magic link label for magic link invitations" do
        owner = signed_in_owner
        create(:invitation, :magic_link, invitable: owner.workspace, invited_by: owner.user)

        get workspace_members_path(owner.workspace)
        expect(response.body).to include(I18n.t("workspaces.members.index.pending_invitations.magic_link"))
      end

      it "shows pending badge" do
        owner = signed_in_owner
        invite_newperson(owner)

        get workspace_members_path(owner.workspace)
        expect(response.body).to include(I18n.t("workspaces.members.index.pending_invitations.pending"))
      end

      it "shows resend and revoke buttons for authorized users" do
        owner = signed_in_owner
        invite_newperson(owner)

        get workspace_members_path(owner.workspace)
        expect(response.body).to include(I18n.t("workspaces.members.index.pending_invitations.resend"))
        expect(response.body).to include(I18n.t("workspaces.members.index.pending_invitations.revoke"))
      end

      it "hides resend and revoke for regular members" do
        owner = create(:membership, :owner)
        invite_newperson(owner)
        sign_in_as(add_member(owner.workspace))

        get workspace_members_path(owner.workspace)
        expect(response.body).not_to include(I18n.t("workspaces.members.index.pending_invitations.resend"))
      end

      it "excludes accepted invitations" do
        owner = signed_in_owner
        invite_newperson(owner).update!(status: "accepted", accepted_at: Time.current)

        get workspace_members_path(owner.workspace)
        expect(response.body).not_to include("newperson@example.com")
      end

      it "excludes expired invitations" do
        owner = signed_in_owner
        invite_newperson(owner).update!(expires_at: 1.day.ago)

        get workspace_members_path(owner.workspace)
        expect(response.body).not_to include("newperson@example.com")
      end

      it "excludes revoked invitations" do
        owner = signed_in_owner
        invite_newperson(owner).revoke!

        get workspace_members_path(owner.workspace)
        expect(response.body).not_to include("newperson@example.com")
      end
    end
  end

  describe "GET /workspaces/:workspace_slug/members/:id/edit" do
    it "renders the role change form" do
      workspace = signed_in_owner.workspace
      target = add_member(workspace)

      get edit_workspace_member_path(workspace, target)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /workspaces/:workspace_slug/members/:id" do
    it "changes the member's role" do
      workspace = signed_in_owner.workspace
      target = add_member(workspace)
      admin_role = Role.system_default!("admin")

      patch workspace_member_path(workspace, target), params: { membership: { role_id: admin_role.id } }
      expect(target.reload.role).to eq(admin_role)
    end

    it "redirects to members list and says the change was saved" do
      workspace = signed_in_owner.workspace
      target = add_member(workspace)

      patch workspace_member_path(workspace, target), params: { membership: { role_id: Role.system_default!("admin").id } }
      expect(response).to redirect_to(workspace_members_path(workspace))
      expect(flash[:notice]).to eq(I18n.t("workspaces.members.update.success"))
    end
  end

  # SEC-1: an Admin can't grant Owner to anyone, themselves included, nor
  # demote an Owner. The persisted role staying unchanged is the assertion.
  describe "PATCH .../members/:id — privilege escalation" do
    it "refuses an admin promoting another member to owner and leaves the role unchanged" do
      workspace = create(:membership, :owner).workspace
      sign_in_as(add_member(workspace, role: :admin))
      target = add_member(workspace)

      patch workspace_member_path(workspace, target), params: { membership: { role_id: Role.system_default!("owner").id } }
      expect(target.reload.role).to eq(Role.system_default!("member"))
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to be_present
    end

    it "refuses an admin promoting their OWN membership to owner" do
      workspace = create(:membership, :owner).workspace
      admin = sign_in_as(add_member(workspace, role: :admin))

      patch workspace_member_path(workspace, admin), params: { membership: { role_id: Role.system_default!("owner").id } }
      expect(admin.reload.role).to eq(Role.system_default!("admin"))
      expect(response).to have_http_status(:redirect)
    end

    # G (SEC-1 follow-up): a blocked escalation attempt is itself a security
    # event. The refusal must reach the admin activity feed, not just 403.
    it "logs the blocked escalation to the admin activity feed" do
      workspace = create(:membership, :owner).workspace
      admin = sign_in_as(add_member(workspace, role: :admin))

      expect {
        patch workspace_member_path(workspace, admin), params: { membership: { role_id: Role.system_default!("owner").id } }
      }.to change { ActivityLog.where(action: "membership.role_grant_blocked").count }.by(1)

      entry = ActivityLog.where(action: "membership.role_grant_blocked").last
      expect(entry.visibility).to eq("admin")
      expect(entry.actor).to eq(admin.user)
      expect(entry.metadata["attempted_role"]).to eq("owner")
    end

    it "refuses an admin editing an owner's membership at all" do
      owner = create(:membership, :owner)
      sign_in_as(add_member(owner.workspace, role: :admin))

      patch workspace_member_path(owner.workspace, owner), params: { membership: { role_id: Role.system_default!("admin").id } }
      expect(owner.reload.role).to eq(Role.system_default!("owner"))
      expect(response).to have_http_status(:redirect)
    end

    it "does not offer the Owner option in an admin's edit dropdown" do
      workspace = create(:membership, :owner).workspace
      sign_in_as(add_member(workspace, role: :admin))
      target = add_member(workspace)

      get edit_workspace_member_path(workspace, target)
      select = Nokogiri::HTML(response.body).at_css("select[name='membership[role_id]']")
      expect(select.to_s).not_to include("Owner")
    end

    it "still lets an admin assign a non-privileged role" do
      workspace = create(:membership, :owner).workspace
      sign_in_as(add_member(workspace, role: :admin))
      target = add_member(workspace)
      admin_role = Role.system_default!("admin")

      patch workspace_member_path(workspace, target), params: { membership: { role_id: admin_role.id } }
      expect(target.reload.role).to eq(admin_role)
    end

    it "refuses an admin reactivating a deactivated owner and leaves it discarded" do
      workspace = create(:membership, :owner).workspace
      sign_in_as(add_member(workspace, role: :admin))
      deactivated_owner = add_member(workspace, role: :owner)
      deactivated_owner.update!(discarded_at: Time.current)

      post workspace_member_reactivation_path(workspace, deactivated_owner)
      expect(deactivated_owner.reload).to be_discarded
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH .../members/:id — viewer actor" do
    it "denies a viewer changing anyone's role and leaves it unchanged" do
      workspace = create(:membership, :owner).workspace
      sign_in_as(create(:membership, workspace: workspace, role: Role.system_default!("viewer")))
      target = add_member(workspace)
      original = target.role

      patch workspace_member_path(workspace, target), params: { membership: { role_id: Role.system_default!("member").id } }
      expect(target.reload.role).to eq(original)
      expect(response).to have_http_status(:redirect)
    end
  end

  # SEC-1 (adjacent): a workspace must always retain at least one owner.
  describe "PATCH .../members/:id — owner floor" do
    it "refuses to demote the sole owner and leaves them owner" do
      owner = signed_in_owner

      patch workspace_member_path(owner.workspace, owner), params: { membership: { role_id: Role.system_default!("admin").id } }
      expect(owner.reload.role).to eq(Role.system_default!("owner"))
      expect(response).to redirect_to(workspace_members_path(owner.workspace))
      expect(flash[:alert]).to eq(I18n.t("workspaces.members.update.cannot_demote_last_owner"))
    end

    it "allows demoting an owner when another owner remains" do
      workspace = signed_in_owner.workspace
      second_owner = add_member(workspace, role: :owner)
      admin_role = Role.system_default!("admin")

      patch workspace_member_path(workspace, second_owner), params: { membership: { role_id: admin_role.id } }
      expect(second_owner.reload.role).to eq(admin_role)
    end
  end

  # C7: the last-owner rescues name their condition (Membership::LastOwner);
  # any other validation failure on these paths surfaces as itself.
  describe "unrelated validation failures are not reported as last-owner" do
    it "PATCH surfaces a non-last-owner RecordInvalid instead of the demote flash" do
      workspace = signed_in_owner.workspace
      target = add_member(workspace)
      allow_any_instance_of(Membership).to receive(:change_role!)
        .and_raise(ActiveRecord::RecordInvalid.new(target))

      patch workspace_member_path(workspace, target), params: { membership: { role_id: Role.system_default!("admin").id } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to be_nil
    end

    it "DELETE surfaces a non-last-owner RecordInvalid instead of the deactivate flash" do
      workspace = signed_in_owner.workspace
      target = add_member(workspace)
      allow_any_instance_of(Membership).to receive(:deactivate!)
        .and_raise(ActiveRecord::RecordInvalid.new(target))

      delete workspace_member_path(workspace, target)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to be_nil
    end
  end

  describe "DELETE /workspaces/:workspace_slug/members/:id" do
    it "deactivates the member" do
      workspace = signed_in_owner.workspace
      target = add_member(workspace)

      delete workspace_member_path(workspace, target)
      expect(target.reload).to be_discarded
    end

    it "redirects to members list" do
      workspace = signed_in_owner.workspace
      target = add_member(workspace)

      delete workspace_member_path(workspace, target)
      expect(response).to redirect_to(workspace_members_path(workspace))
    end
  end

  # Reactivating is the create of a reactivation nested under the member (#1007).
  describe "POST /workspaces/:workspace_slug/members/:id/reactivation" do
    it "reactivates the member" do
      workspace = signed_in_owner.workspace
      target = add_member(workspace)
      target.update!(discarded_at: Time.current)

      post workspace_member_reactivation_path(workspace, target)
      expect(target.reload).not_to be_discarded
      expect(response).to redirect_to(workspace_members_path(workspace))
      expect(flash[:notice]).to eq(I18n.t("workspaces.members.reactivations.create.reactivated"))
    end
  end

  # Transferring ownership is the create of an ownership transfer nested under the member (#1007).
  describe "POST /workspaces/:workspace_slug/members/:id/ownership_transfer" do
    it "transfers ownership" do
      owner = signed_in_owner
      target = add_member(owner.workspace)

      post workspace_member_ownership_transfer_path(owner.workspace, target)
      expect(target.reload.role).to eq(Role.system_default!("owner"))
      expect(owner.reload.role).to eq(Role.system_default!("admin"))
      expect(response).to redirect_to(workspace_members_path(owner.workspace))
      expect(flash[:notice]).to eq(I18n.t("workspaces.members.ownership_transfers.create.transferred"))
    end
  end

  describe "member authorization" do
    it "denies role change for regular members" do
      owner = create(:membership, :owner)
      member = add_member(owner.workspace)
      target = add_member(owner.workspace)
      sign_in_as(member)

      patch workspace_member_path(owner.workspace, target), params: { membership: { role_id: owner.role_id } }
      expect(response).to have_http_status(:redirect)
    end

    it "denies edit" do
      workspace = create(:membership, :owner).workspace
      target = add_member(workspace)
      sign_in_as(add_member(workspace))

      get edit_workspace_member_path(workspace, target)
      expect(response).to have_http_status(:redirect)
    end

    it "denies reactivate" do
      workspace = create(:membership, :owner).workspace
      target = add_member(workspace)
      sign_in_as(add_member(workspace))
      target.update!(discarded_at: Time.current)

      post workspace_member_reactivation_path(workspace, target)
      expect(target.reload).to be_discarded
    end

    it "denies transfer_ownership" do
      workspace = create(:membership, :owner).workspace
      target = add_member(workspace)
      sign_in_as(add_member(workspace))

      post workspace_member_ownership_transfer_path(workspace, target)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "DELETE last owner" do
    it "returns redirect with alert when deactivating last owner" do
      owner = create(:membership, :owner)
      sign_in_as(add_member(owner.workspace, role: :admin))

      delete workspace_member_path(owner.workspace, owner)
      expect(response).to redirect_to(workspace_members_path(owner.workspace))
      expect(flash[:alert]).to be_present
    end
  end
end

RSpec.describe "Workspaces::Members destroy", type: :request do
  def sign_in_as(membership)
    sign_in(membership.user)
    membership
  end

  describe "DELETE /workspaces/:slug/members/:id" do
    context "user leaving their own (non-personal) membership" do
      it "deactivates the membership and redirects to /workspaces with the 'left' flash" do
        workspace = create(:workspace, name: "Acme")
        mine = sign_in_as(create(:membership, workspace: workspace))
        create(:membership, :owner, workspace: workspace)

        delete workspace_member_path(workspace, mine)
        expect(response).to redirect_to(workspaces_path)
        follow_redirect!
        expect(flash[:notice]).to eq(I18n.t("workspaces.members.destroy.left", workspace_name: workspace.name))
        expect(mine.reload.discarded_at).to be_present
      end
    end

    context "user trying to leave their personal workspace" do
      it "is forbidden by the policy" do
        workspace = create(:workspace, name: "Acme")
        personal = sign_in_as(create(:membership, :owner, workspace: workspace))
        personal.user.update!(personal_workspace_id: workspace.id)

        delete workspace_member_path(workspace, personal)
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
        expect(personal.reload.discarded_at).to be_nil
      end
    end

    context "user trying to leave as the last owner" do
      it "is forbidden and the membership remains kept" do
        workspace = create(:workspace, name: "Acme")
        sole_owner = sign_in_as(create(:membership, :owner, workspace: workspace))

        delete workspace_member_path(workspace, sole_owner)
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
        expect(sole_owner.reload.discarded_at).to be_nil
      end
    end

    # #526: the self-leave last-owner refusal is a race net behind the policy's
    # sole-owner check; the assertion is which of the two last-owner alerts shows.
    context "when the other owner vanishes between the policy check and the write" do
      it "redirects to /workspaces with the cannot-leave alert and keeps the membership" do
        workspace = create(:workspace, name: "Acme")
        mine = sign_in_as(create(:membership, :owner, workspace: workspace))
        create(:membership, :owner, workspace: workspace)
        allow_any_instance_of(Membership).to receive(:deactivate!)
          .and_raise(Membership::LastOwner.new(mine))

        delete workspace_member_path(workspace, mine)

        expect(response).to redirect_to(workspaces_path)
        follow_redirect!
        expect(flash[:alert]).to eq(I18n.t("workspaces.members.destroy.cannot_leave_last_owner"))
        expect(mine.reload.discarded_at).to be_nil
      end
    end

    context "admin deactivating another member (existing case)" do
      it "deactivates and redirects to the members table (unchanged behavior)" do
        workspace = create(:workspace, name: "Acme")
        sign_in_as(create(:membership, :admin, workspace: workspace))
        other = create(:membership, workspace: workspace)
        create(:membership, :owner, workspace: workspace)

        delete workspace_member_path(workspace, other)
        expect(response).to redirect_to(workspace_members_path(workspace))
        follow_redirect!
        expect(flash[:notice]).to eq(I18n.t("workspaces.members.destroy.deactivated"))
        expect(other.reload.discarded_at).to be_present
      end
    end

    # #933: the controller is the only caller of #deactivate!, so it is the only
    # place the actor can be named; without it every removal reads as a system action.
    context "notifying the people a removal concerns" do
      def removal_message_for(recipient)
        Noticed::Notification
          .where(type: "WorkspaceMemberRemovedNotifier::Notification", recipient: recipient)
          .last&.message
      end

      it "names the acting owner, so the removed member reads it as a removal" do
        workspace = create(:workspace, name: "Acme")
        owner = sign_in_as(create(:membership, :owner, workspace: workspace))
        other = create(:membership, workspace: workspace)
        create(:membership, :owner, workspace: workspace)

        delete workspace_member_path(workspace, other)

        expect(removal_message_for(other.user))
          .to eq("#{other.user.first_name} was removed from #{workspace.name}")
        expect(removal_message_for(owner.user)).to be_nil
      end

      # The other owner reads this one: recipients are the removed member plus
      # the owners, and a plain member hears nothing of someone else's removal.
      it "reads as a departure when the member removes their own membership" do
        workspace = create(:workspace, name: "Acme")
        owner = sign_in_as(create(:membership, :owner, workspace: workspace))
        other = create(:membership, workspace: workspace)
        bystander_owner = create(:membership, :owner, workspace: workspace)

        delete workspace_member_path(workspace, owner)

        expect(removal_message_for(bystander_owner.user))
          .to eq("#{owner.user.first_name} left #{workspace.name}")
        expect(removal_message_for(other.user)).to be_nil
      end
    end

    context "non-member tries to delete someone else's membership" do
      it "is forbidden" do
        workspace = create(:workspace, name: "Acme")
        target = create(:membership, workspace: workspace)
        sign_in(create(:user))

        delete workspace_member_path(workspace, target)
        expect(response).to have_http_status(:redirect)  # set_workspace redirects to /workspaces on RecordNotFound
      end
    end
  end
end
