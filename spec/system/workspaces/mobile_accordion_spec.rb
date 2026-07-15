# frozen_string_literal: true

require "rails_helper"

# Mobile-viewport behavior for the workspace-scoped (application layout)
# header accordion (below md). The accordion holds only GLOBAL chrome now
# (workspace switcher, user menu, theme toggle); the workspace section sub-nav
# (Overview/Settings) lives in an in-page strip, not here. Mirrors the
# settings accordion spec.
RSpec.describe "Workspace pages — mobile accordion", type: :system, js: true do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, max_members: 50) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    sign_in_via_form(user)
    cdp_resize(375, 667)
  end

  it "shows the hamburger and reveals global chrome on tap (not the section sub-nav)" do
    visit workspace_path(workspace)
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      expect(page).to have_link(I18n.t("navigation.all_workspaces"))    # global chrome
    end
  end

  it "auto-closes on link tap inside the panel" do
    visit workspace_path(workspace)
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      # A global-chrome link (the section sub-nav no longer lives in the panel).
      click_link I18n.t("navigation.all_workspaces")
    end
    expect(page).to have_current_path(workspaces_path)
    expect(page).to have_css("[data-mobile-menu-target='menu'].hidden", visible: :all)
  end

  it "passes axe AAA both themes both states" do
    visit workspace_path(workspace)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations (collapsed):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    click_button I18n.t("navigation.mobile_menu.open")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations (expanded):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
