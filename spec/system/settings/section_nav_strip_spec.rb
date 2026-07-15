require "rails_helper"

RSpec.describe "Settings section-nav strip (mobile)", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in_via_form(user)
    cdp_resize(390, 780)
  end

  it "shows the identity section nav as an in-page strip, not in the hamburger" do
    visit edit_settings_profile_path
    # The strip is a labeled nav in the content, current page marked
    expect(page).to have_css("nav[aria-labelledby] a[aria-current='page']", text: I18n.t("settings.sidebar.items.profile"))
    # It is NOT inside the header's mobile panel
    expect(page).to have_no_css("#mobile-menu-panel nav a", text: I18n.t("settings.sidebar.items.security"))
  end

  it "navigates to a sibling page from the strip" do
    visit edit_settings_profile_path
    within("nav[aria-labelledby='section-nav-strip-heading']") do
      click_on I18n.t("settings.sidebar.items.appearance")
    end
    expect(page).to have_current_path(edit_settings_theme_preference_path)
  end
end
