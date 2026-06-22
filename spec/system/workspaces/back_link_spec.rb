require "rails_helper"

RSpec.describe "Workspace back-link navigation", type: :system do
  let(:user) { create(:user, first_name: "Owner", last_name: "User") }
  let(:workspace) { create(:workspace, name: "Acme Inc", max_members: 50) }
  let!(:owner_membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before do
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))
    token = MagicLinkToken.where(email: user.email_address).order(:created_at).last.token
    visit magic_link_callback_path(token: token)
    expect(page).to have_css("#user-menu-button")
  end

  let(:back_label) { I18n.t("navigation.back_to_workspace", workspace: workspace.name) }

  describe "on settings-hub pages (post route-consolidation panel review)" do
    # The header workspace switcher (#workspace-switcher-button, Phase 2b)
    # is the canonical context-escape from settings — clicking another
    # workspace navigates to that workspace's dashboard.
    # The redundant <nav>-wrapped back-link was removed from settings
    # layout after a Jason Fried-led panel review found it created visual
    # divorce between the sidebar and the main content.

    it "does not show the back-link on the members page" do
      visit workspace_members_path(workspace)
      expect(page).not_to have_link(back_label)
    end

    it "does not show the back-link on the limits & plan (settings) page" do
      visit edit_workspace_settings_path(workspace)
      expect(page).not_to have_link(back_label)
    end
  end

  describe "on the workspace show page" do
    it "does not show the back-link (tautological — already there)" do
      visit workspace_path(workspace)
      expect(page).not_to have_link(back_label)
    end
  end
end
