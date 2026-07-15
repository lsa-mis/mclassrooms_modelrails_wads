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
    # spawns the Cuprite session lazily on first visit (via sign_in
    # above), so the page is live by the time we resize.
    cdp_resize(375, 667)
  end

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))
    token = MagicLinkToken.where(email: user.email_address).order(:created_at).last.token
    visit magic_link_callback_path(token: token)
    expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
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
