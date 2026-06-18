# frozen_string_literal: true

require "rails_helper"

# Mobile-viewport audit for the v2 four-card preferences page. The motivation
# behind this redesign was that the v1 5×3 matrix had no good responsive
# behavior at iPhone SE width (375px); horizontal-scroll hid half the
# controls below the fold. v2's parallel-list IA stacks cleanly. This spec
# locks that mobile fitness in place so future tweaks can't regress it.
RSpec.describe "Notification preferences — mobile viewport", type: :system, js: true do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:password)    { "MobilePrefs#42!" }
  let(:user)        { create(:user, password: password) }

  before do
    user.create_preferences!(timezone: "America/New_York")
    sign_in_via_form(user)
    # iPhone SE viewport — tightest realistic phone we target. Capybara
    # spawns the Playwright session lazily on first visit (via sign_in
    # above), so the page is live by the time we resize.
    page.driver.with_playwright_page do |pw_page|
      pw_page.set_viewport_size(width: 375, height: 667)
    end
  end

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: password
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  it "renders without horizontal scroll at 375x667 (iPhone SE)" do
    visit edit_settings_notification_preferences_path
    expect(page).to have_text(I18n.t("settings.pages.notifications.h1"))

    doc_width    = page.evaluate_script("document.documentElement.scrollWidth")
    client_width = page.evaluate_script("document.documentElement.clientWidth")

    expect(doc_width).to be <= client_width,
      "Horizontal scroll detected at mobile viewport: scrollWidth=#{doc_width} > clientWidth=#{client_width}. " \
      "The v1 matrix had this regression; v2 should stack."
  end

  it "passes AAA audit at mobile viewport in both light + dark themes" do
    visit edit_settings_notification_preferences_path
    expect(page).to have_text(I18n.t("settings.pages.notifications.h1"))

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Mobile AAA violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
