# frozen_string_literal: true

require "rails_helper"

# Baseline AAA audit for /account/notification_preferences/edit. Establishes
# the WCAG 2.2 AAA bar BEFORE the visual refactor in this PR, so any
# regression introduced by the refactor surfaces here. Spec also runs against
# the new card layout once Phase 1 lands; the assertions are layout-agnostic.
RSpec.describe "Account Notification Preferences — AAA accessibility", type: :system, js: true do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:password)    { "VerifyPrefs#42!" }
  let(:user)        { create(:user, password: password) }

  before do
    user.create_preferences!(timezone: "America/New_York")
    sign_in_via_form(user)
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

  it "passes AAA audit on the preferences edit page in both light + dark modes" do
    visit edit_settings_notification_preferences_path
    expect(page).to have_text(I18n.t("settings.pages.notifications.h1"))

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  # Locks the Phase 0 visual swap: each section of the preferences page
  # renders inside a rounded-2xl card surface. Content (the v1 5×3 matrix,
  # digest controls, retention dropdown) is unchanged — only the wrapping
  # is. PR-3 will swap the content to parallel-list rows.
  it "renders each preferences section inside a rounded-2xl card surface" do
    visit edit_settings_notification_preferences_path
    expect(page).to have_css("section.rounded-2xl.bg-surface-raised", minimum: 3)
  end
end
