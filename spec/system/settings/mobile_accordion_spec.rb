# frozen_string_literal: true

require "rails_helper"

# Mobile-viewport behavior for the settings-hub header accordion (below md).
# Replaces the off-canvas drawer pattern (Path Z): the header expands
# downward to reveal the same _settings_sidebar partial inline via
# content_for(:mobile_menu_sidebar). No modal context, no overlay, no
# focus trap. Same coverage profile as the prior mobile_drawer_spec:
# toggle visible, opens on tap, auto-closes on link tap, axe AAA both
# themes both states.
RSpec.describe "Settings hub — mobile accordion", type: :system, js: true do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    sign_in_via_form(user)
    page.driver.with_playwright_page do |pw_page|
      pw_page.set_viewport_size(width: 375, height: 667)
    end
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

  it "auto-closes the accordion when a sidebar link inside is tapped" do
    visit edit_settings_profile_path
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      click_link I18n.t("settings.sidebar.items.notifications")
    end
    expect(page).to have_current_path(edit_settings_notification_preferences_path)
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
