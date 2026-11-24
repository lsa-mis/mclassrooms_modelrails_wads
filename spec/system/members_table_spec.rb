require "rails_helper"

RSpec.describe "Members table", type: :system do
  def signed_in_owner
    user = create(:user, first_name: "Owner", last_name: "User", password: "SecureP@ssw0rd123!")
    owner = add_member(create(:workspace, max_members: 50), role: :owner, user: user)
    sign_in_via_form(user)
    expect(page).to have_css("#user-menu-button")
    owner
  end

  def seed_assignable_roles
    %w[admin member viewer].each { |slug| Role.system_default!(slug) }
  end

  describe "members index page" do
    def add_alice_and_bob(workspace)
      alice = create(:user, first_name: "Alice", last_name: "Anderson")
      bob = create(:user, first_name: "Bob", last_name: "Baker")
      add_member(workspace, role: :admin, user: alice)
      add_member(workspace, user: bob)
    end

    it "displays members in a table" do
      workspace = signed_in_owner.workspace
      add_alice_and_bob(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_text("Alice Anderson")
      expect(page).to have_text("Bob Baker")
      expect(page).to have_selector("h1", text: "Members")
      expect(page).to have_css("#workspace-name-heading", text: workspace.name)
    end

    it "shows a search field" do
      workspace = signed_in_owner.workspace
      add_alice_and_bob(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_field(type: "search")
    end

    it "shows role and status filter dropdowns" do
      workspace = signed_in_owner.workspace
      add_alice_and_bob(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_select("role")
      expect(page).to have_select("status")
    end

    it "shows sortable column headers as links" do
      workspace = signed_in_owner.workspace
      add_alice_and_bob(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_link(I18n.t("workspaces.members.index.name"))
      expect(page).to have_link(I18n.t("workspaces.members.index.email"))
      expect(page).to have_link(I18n.t("workspaces.members.index.role"))
    end

    it "marks unsorted columns as sortable via aria-sort=none" do
      workspace = signed_in_owner.workspace
      add_alice_and_bob(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_css('th[aria-sort="none"]', count: 3)
    end

    it "announces the active sort column and direction via aria-sort" do
      workspace = signed_in_owner.workspace
      add_alice_and_bob(workspace)

      visit workspace_members_path(workspace, sort: "name", direction: "asc")
      expect(page).to have_css('th[aria-sort="ascending"]', count: 1)
      expect(page).to have_css('th[aria-sort="none"]', count: 2)

      visit workspace_members_path(workspace, sort: "email", direction: "desc")
      expect(page).to have_css('th[aria-sort="descending"]', count: 1)
      expect(page).to have_css('th[aria-sort="none"]', count: 2)
    end

    it "shows status badges" do
      workspace = signed_in_owner.workspace
      add_alice_and_bob(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_text(I18n.t("workspaces.members.index.active"))
    end

    it "shows action links for authorized users" do
      workspace = signed_in_owner.workspace
      add_alice_and_bob(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_text(I18n.t("workspaces.members.index.edit_role"))
      expect(page).to have_button(I18n.t("workspaces.members.index.deactivate"))
    end

    it "shows empty state when filtering yields no results" do
      workspace = signed_in_owner.workspace
      add_alice_and_bob(workspace)

      visit workspace_members_path(workspace, q: "nonexistent_xyz_person")
      expect(page).to have_text(I18n.t("workspaces.members.index.empty"))
    end

    it "wraps results in a Turbo Frame" do
      workspace = signed_in_owner.workspace
      add_alice_and_bob(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_css("turbo-frame#members_results")
    end
  end

  describe "deactivated member display" do
    def add_deactivated_member(workspace)
      deactivated_user = create(:user, first_name: "Deactivated", last_name: "Member")
      add_member(workspace, user: deactivated_user).update!(discarded_at: Time.current)
    end

    it "shows deactivated badge for discarded members" do
      workspace = signed_in_owner.workspace
      add_deactivated_member(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_text(I18n.t("workspaces.members.index.deactivated"))
    end

    it "shows reactivate button for deactivated members" do
      workspace = signed_in_owner.workspace
      add_deactivated_member(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_button(I18n.t("workspaces.members.index.reactivate"))
    end
  end

  describe "accessibility (axe-core)" do
    it "members page passes automated accessibility checks (light + dark)" do
      workspace = signed_in_owner.workspace
      add_member(workspace, role: :admin, user: create(:user, first_name: "Alice", last_name: "Anderson"))
      axe_options = { runOnly: { type: "tag", values: [ "wcag2aaa" ] } }

      visit workspace_members_path(workspace)
      # Dismiss any toast notification before running axe
      page.execute_script("document.querySelectorAll('[data-controller=\"toast-pill\"], [data-controller=\"toast-card\"]').forEach(el => el.remove())")
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  describe "demoting the last owner via inline edit (SEC-1)" do
    it "announces the refusal in a toast and leaves the role unchanged" do
      owner = signed_in_owner
      seed_assignable_roles

      visit workspace_members_path(owner.workspace)
      within "##{ActionView::RecordIdentifier.dom_id(owner)}" do
        click_link I18n.t("workspaces.members.index.edit_role")
        select "Admin", from: I18n.t("workspaces.members.edit.role_label")
        click_button I18n.t("workspaces.members.edit.submit")
      end

      expect(page).to have_text(I18n.t("workspaces.members.update.cannot_demote_last_owner"))
      expect(owner.reload.role.slug).to eq("owner")
    end
  end

  describe "table structure" do
    def add_test_member(workspace)
      add_member(workspace, user: create(:user, first_name: "Test", last_name: "Member"))
    end

    it "uses semantic table markup" do
      workspace = signed_in_owner.workspace
      add_test_member(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_css("table thead th[scope='col']", minimum: 5)
      expect(page).to have_css("table tbody tr", minimum: 2)
    end

    it "has unique row IDs for Turbo Stream targeting" do
      workspace = signed_in_owner.workspace
      add_test_member(workspace)

      visit workspace_members_path(workspace)
      expect(page).to have_css("tr[id^='membership_']")
    end
  end

  describe "invite button" do
    it "shows invite button for owner" do
      visit workspace_members_path(signed_in_owner.workspace)
      expect(page).to have_link(I18n.t("workspaces.members.index.invite_member"))
    end

    it "links to the invitation form" do
      workspace = signed_in_owner.workspace

      visit workspace_members_path(workspace)
      expect(page).to have_link(
        I18n.t("workspaces.members.index.invite_member"),
        href: new_workspace_invitation_path(workspace)
      )
    end

    it "hides invite button for regular members" do
      workspace = signed_in_owner.workspace
      regular = create(:user, first_name: "Regular", last_name: "Member", password: "SecureP@ssw0rd123!")
      add_member(workspace, user: regular)
      # The avatar button never re-renders on notification arrival (D1), so this click hits a live element.
      find("#user-menu-button").click
      click_button I18n.t("navigation.sign_out")
      expect(page).to have_text(I18n.t("sessions.new.title"))
      sign_in_via_form(regular)
      expect(page).to have_css("#user-menu-button")
      visit workspace_members_path(workspace)
      expect(page).to have_css("h1", text: I18n.t("settings.pages.workspace_members.h1_html"))
      expect(page).not_to have_link(I18n.t("workspaces.members.index.invite_member"))
    end
  end

  describe "pending invitations section" do
    def invite_pending(owner)
      create(:invitation, invitable: owner.workspace, email: "invited@example.com", invited_by: owner.user)
    end

    it "shows pending invitations interleaved in the unified members table" do
      owner = signed_in_owner
      invite_pending(owner)

      visit workspace_members_path(owner.workspace)
      expect(page).to have_text("invited@example.com")
      expect(page).to have_text(I18n.t("workspaces.members.index.pending_invitations.pending"))
    end

    it "filters to only invitations when status=pending (URL-driven)" do
      owner = signed_in_owner
      invite_pending(owner)

      visit workspace_members_path(owner.workspace, status: "pending")
      # Scoped to the table: "Owner User" also appears in the user-menu chrome.
      within("table") do
        expect(page).to have_text("invited@example.com")
        expect(page).not_to have_text("Owner User")
      end
    end

    it "filters to only active members when status=active (URL-driven)" do
      owner = signed_in_owner
      invite_pending(owner)

      visit workspace_members_path(owner.workspace, status: "active")
      within("table") do
        expect(page).to have_text("Owner User")
        expect(page).not_to have_text("invited@example.com")
      end
    end

    it "filters via the dropdown control (interactive — exercises the form submit path)" do
      owner = signed_in_owner
      invite_pending(owner)

      visit workspace_members_path(owner.workspace)
      within("table") do
        expect(page).to have_text("Owner User")
        expect(page).to have_text("invited@example.com")
      end
      select I18n.t("workspaces.members.index.status_pending"),
        from: I18n.t("workspaces.members.index.status")
      within("table") do
        expect(page).to have_text("invited@example.com")
        expect(page).not_to have_text("Owner User")
      end
    end

    it "shows pending badge" do
      owner = signed_in_owner
      invite_pending(owner)

      visit workspace_members_path(owner.workspace)
      expect(page).to have_text(I18n.t("workspaces.members.index.pending_invitations.pending"))
    end

    it "shows resend and revoke buttons for owner" do
      owner = signed_in_owner
      invite_pending(owner)

      visit workspace_members_path(owner.workspace)
      expect(page).to have_button(I18n.t("workspaces.members.index.pending_invitations.resend"))
      expect(page).to have_button(I18n.t("workspaces.members.index.pending_invitations.revoke"))
    end
  end
end
