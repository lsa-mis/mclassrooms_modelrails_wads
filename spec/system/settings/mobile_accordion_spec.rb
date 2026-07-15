# frozen_string_literal: true

require "rails_helper"

# Mobile-viewport behavior for the header accordion (below md). The accordion
# holds only GLOBAL chrome now — workspace switcher, user menu, theme toggle;
# the section sub-nav lives in an in-page strip (see section_nav_strip_spec),
# not here. No modal context, no overlay, no focus trap. Coverage: toggle
# visible, opens on tap, auto-closes when a link inside is tapped, axe AAA both
# themes both states.
RSpec.describe "Settings hub — mobile accordion", type: :system, js: true do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    sign_in_via_form(user)
    cdp_resize(375, 667)
  end

  it "shows the hamburger toggle below md" do
    visit edit_settings_profile_path
    expect(page).to have_button(I18n.t("navigation.mobile_menu.open"))
  end

  it "opens the accordion when the hamburger is tapped" do
    visit edit_settings_profile_path
    click_button I18n.t("navigation.mobile_menu.open")
    expect(page.find("[data-mobile-menu-target='button']"))
      .to match_selector("[aria-expanded='true']")
    expect(page).to have_css("[data-mobile-menu-target='menu']:not(.hidden)")
  end

  it "reveals only global chrome on tap, not the section sub-nav" do
    visit edit_settings_profile_path
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      expect(page).to have_link(I18n.t("navigation.all_workspaces"))          # global chrome
      expect(page).to have_no_link(I18n.t("settings.sidebar.items.security")) # sub-nav lives in the in-page strip
    end
  end

  it "auto-closes the accordion when a link inside is tapped" do
    visit edit_settings_profile_path
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      # A global-chrome link (the section sub-nav no longer lives in the panel).
      click_link I18n.t("navigation.all_workspaces")
    end
    expect(page).to have_current_path(workspaces_path)
    expect(page).to have_css("[data-mobile-menu-target='menu'].hidden", visible: :all)
  end

  it "passes axe AAA both themes in both accordion states" do
    visit edit_settings_profile_path

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations (collapsed):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    click_button I18n.t("navigation.mobile_menu.open")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations (expanded):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
