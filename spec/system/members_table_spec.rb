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
    let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aa" ] } } }
    let!(:alice) { create(:user, first_name: "Alice", last_name: "Anderson") }
    let!(:alice_membership) { create(:membership, :admin, user: alice, workspace: workspace) }

    it "members page passes automated accessibility checks" do
      visit workspace_members_path(workspace)
      # Dismiss any toast notification before running axe
      page.execute_script("document.querySelectorAll('[data-controller=\"toast\"]').forEach(el => el.remove())")
      expect(axe_clean?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations(axe_options).join("\n")}"
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
end
