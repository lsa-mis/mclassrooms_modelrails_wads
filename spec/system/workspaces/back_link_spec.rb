require "rails_helper"

RSpec.describe "Workspace back-link navigation", type: :system do
  let(:user) { create(:user, first_name: "Owner", last_name: "User") }
  let(:workspace) { create(:workspace, name: "Acme Inc", max_members: 50) }
  let!(:owner_membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before do
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_link(I18n.t("navigation.workspaces"))
  end

  describe "on workspace-scoped pages" do
    let(:back_label) { I18n.t("navigation.back_to_workspace", workspace: workspace.name) }

    it "shows the back-link on the members page" do
      visit workspace_members_path(workspace)
      expect(page).to have_link(back_label, href: workspace_path(workspace))
    end

    it "shows the back-link on the settings page" do
      visit edit_workspace_settings_path(workspace)
      expect(page).to have_link(back_label, href: workspace_path(workspace))
    end

    it "navigates back to the workspace overview when clicked" do
      visit workspace_members_path(workspace)
      click_link back_label
      expect(page).to have_current_path(workspace_path(workspace))
    end
  end

  describe "on the workspace show page" do
    it "does not show the back-link (tautological — already there)" do
      visit workspace_path(workspace)
      expect(page).not_to have_link(I18n.t("navigation.back_to_workspace", workspace: workspace.name))
    end
  end
end
