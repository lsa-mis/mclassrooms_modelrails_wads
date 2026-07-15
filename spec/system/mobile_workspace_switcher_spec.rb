# frozen_string_literal: true

require "rails_helper"

# System spec: mobile workspace switcher in the hamburger panel.
#
# At a 375px viewport the desktop switcher (`hidden md:block`) is invisible;
# this spec verifies the mobile inline list variant is reachable via the
# hamburger, lists the user's workspaces, and navigates on selection.
RSpec.describe "Mobile workspace switcher — hamburger panel", type: :system, js: true do
  let(:user) { create(:user) }
  let!(:second_workspace) do
    ws = create(:workspace, max_members: 50)
    create(:membership, :owner, user: user, workspace: ws)
    ws
  end

  before do
    sign_in_via_form(user)
    cdp_resize(375, 667)
  end

  it "shows both workspaces in the mobile panel after opening the hamburger" do
    user.reload
    personal = user.personal_workspace

    visit workspaces_path

    click_button I18n.t("navigation.mobile_menu.open")

    within("[data-mobile-menu-target='menu']") do
      expect(page).to have_link(personal.name, href: workspace_path(personal))
      expect(page).to have_link(second_workspace.name, href: workspace_path(second_workspace))
    end
  end

  it "navigates to the selected workspace when a mobile switcher link is clicked" do
    visit workspaces_path

    click_button I18n.t("navigation.mobile_menu.open")

    within("[data-mobile-menu-target='menu']") do
      click_link second_workspace.name
    end

    expect(page).to have_current_path(workspace_path(second_workspace))
  end
end
