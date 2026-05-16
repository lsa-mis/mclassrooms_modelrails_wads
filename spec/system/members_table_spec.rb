require "rails_helper"

RSpec.describe "Members table", type: :system do
  let(:user) { create(:user, first_name: "Owner", last_name: "User", password: "SecureP@ssw0rd123!") }
  let(:workspace) { create(:workspace, max_members: 50) }
  let!(:owner_membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before do
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_link(I18n.t("navigation.workspaces"))
  end

  describe "members index page" do
    let!(:alice) { create(:user, first_name: "Alice", last_name: "Anderson") }
    let!(:bob) { create(:user, first_name: "Bob", last_name: "Baker") }
    let!(:alice_membership) { create(:membership, :admin, user: alice, workspace: workspace) }
    let!(:bob_membership) { create(:membership, user: bob, workspace: workspace) }

    it "displays members in a table" do
      visit workspace_members_path(workspace)
      expect(page).to have_text("Alice Anderson")
      expect(page).to have_text("Bob Baker")
      expect(page).to have_text(I18n.t("workspaces.members.index.title"))
    end

    it "shows a search field" do
      visit workspace_members_path(workspace)
      expect(page).to have_field(type: "search")
    end

    it "shows role and status filter dropdowns" do
      visit workspace_members_path(workspace)
      expect(page).to have_select("role")
      expect(page).to have_select("status")
    end

    it "shows sortable column headers as links" do
      visit workspace_members_path(workspace)
      expect(page).to have_link(I18n.t("workspaces.members.index.name"))
      expect(page).to have_link(I18n.t("workspaces.members.index.email"))
      expect(page).to have_link(I18n.t("workspaces.members.index.role"))
    end

    it "shows status badges" do
      visit workspace_members_path(workspace)
      expect(page).to have_text(I18n.t("workspaces.members.index.active"))
    end

    it "shows action links for authorized users" do
      visit workspace_members_path(workspace)
      expect(page).to have_text(I18n.t("workspaces.members.index.edit_role"))
      expect(page).to have_button(I18n.t("workspaces.members.index.deactivate"))
    end

    it "shows empty state when filtering yields no results" do
      visit workspace_members_path(workspace, q: "nonexistent_xyz_person")
      expect(page).to have_text(I18n.t("workspaces.members.index.empty"))
    end

    it "wraps results in a Turbo Frame" do
      visit workspace_members_path(workspace)
      expect(page).to have_css("turbo-frame#members_results")
    end
  end

  describe "deactivated member display" do
    let!(:deactivated_user) { create(:user, first_name: "Deactivated", last_name: "Member") }
    let!(:deactivated_membership) { create(:membership, user: deactivated_user, workspace: workspace) }

    before { deactivated_membership.discard! }

    it "shows deactivated badge for discarded members" do
      visit workspace_members_path(workspace)
      expect(page).to have_text(I18n.t("workspaces.members.index.deactivated"))
    end

    it "shows reactivate button for deactivated members" do
      visit workspace_members_path(workspace)
      expect(page).to have_button(I18n.t("workspaces.members.index.reactivate"))
    end
  end

  describe "accessibility (axe-core)" do
    # Audits at WCAG 2.2 AAA — the project standard. Both light and dark.
    let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
    let!(:alice) { create(:user, first_name: "Alice", last_name: "Anderson") }
    let!(:alice_membership) { create(:membership, :admin, user: alice, workspace: workspace) }

    it "members page passes automated accessibility checks (light + dark)" do
      visit workspace_members_path(workspace)
      # Dismiss any toast notification before running axe
      page.execute_script("document.querySelectorAll('[data-controller=\"toast-pill\"], [data-controller=\"toast-card\"]').forEach(el => el.remove())")
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  describe "table structure" do
    let!(:member) { create(:user, first_name: "Test", last_name: "Member") }
    let!(:member_membership) { create(:membership, user: member, workspace: workspace) }

    it "uses semantic table markup" do
      visit workspace_members_path(workspace)
      expect(page).to have_css("table thead th[scope='col']", minimum: 5)
      expect(page).to have_css("table tbody tr", minimum: 2)
    end

    it "has unique row IDs for Turbo Stream targeting" do
      visit workspace_members_path(workspace)
      expect(page).to have_css("tr[id^='membership_']")
    end
  end

  describe "invite button" do
    it "shows invite button for owner" do
      visit workspace_members_path(workspace)
      expect(page).to have_link(I18n.t("workspaces.members.index.invite_member"))
    end

    it "links to the invitation form" do
      visit workspace_members_path(workspace)
      expect(page).to have_link(
        I18n.t("workspaces.members.index.invite_member"),
        href: new_workspace_invitation_path(workspace)
      )
    end

    it "hides invite button for regular members" do
      regular = create(:user, first_name: "Regular", last_name: "Member", password: "SecureP@ssw0rd123!")
      create(:membership, user: regular, workspace: workspace)
      # Sign out the owner first via user menu dropdown.
      # The avatar button is now stable across broadcasts:
      # NotificationBroadcaster replaces only the sr-only label span
      # (#notifications_avatar_button_label_frame), not the button itself.
      # Clicks landing during a notification arrival still hit a live
      # #user-menu-button, so the retry-on-detach workaround is no longer
      # needed here. See PR fixing the broadcast frame swap race.
      find("#user-menu-button").click
      click_button I18n.t("navigation.sign_out")
      expect(page).to have_text(I18n.t("sessions.new.title"))
      # Sign in as regular member
      fill_in I18n.t("sessions.new.email_label"), with: regular.email_address
      click_button I18n.t("sessions.new.continue")
      fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
      click_button I18n.t("sessions.password_form.submit")
      expect(page).to have_link(I18n.t("navigation.workspaces"))
      visit workspace_members_path(workspace)
      expect(page).not_to have_link(I18n.t("workspaces.members.index.invite_member"))
    end
  end

  describe "pending invitations section" do
    let!(:pending_invitation) do
      create(:invitation, invitable: workspace, email: "invited@example.com",
             invited_by: user)
    end

    it "shows pending invitations" do
      visit workspace_members_path(workspace)
      expect(page).to have_text(I18n.t("workspaces.members.index.pending_invitations.title"))
      expect(page).to have_text("invited@example.com")
    end

    it "shows pending badge" do
      visit workspace_members_path(workspace)
      expect(page).to have_text(I18n.t("workspaces.members.index.pending_invitations.pending"))
    end

    it "shows resend and revoke buttons for owner" do
      visit workspace_members_path(workspace)
      expect(page).to have_button(I18n.t("workspaces.members.index.pending_invitations.resend"))
      expect(page).to have_button(I18n.t("workspaces.members.index.pending_invitations.revoke"))
    end
  end
end
