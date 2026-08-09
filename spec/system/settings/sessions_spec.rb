require "rails_helper"

RSpec.describe "Active devices (settings/sessions)", type: :system do
  let(:user) { create(:user, first_name: "Sam", last_name: "Session") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    token = MagicLinkToken.where(email: user.email_address).order(:created_at).last.token
    visit magic_link_callback_path(token: token)
    expect(page).to have_css("#user-menu-button")
    # A second, older "device" so the list renders the current marker AND a
    # revocable row.
    user.sessions.create!(user_agent: "Mozilla/5.0 (Windows NT 10.0) Firefox/130.0", ip_address: "10.0.0.8")
  end

  it "lists devices with a programmatic current-device marker, accessibly in both themes" do
    visit settings_sessions_path
    expect(page).to have_text(I18n.t("settings.sessions.index.current_device"))
    expect(page).to have_text("Firefox on Windows")
    page.execute_script("document.querySelectorAll('[data-controller=\"toast-pill\"], [data-controller=\"toast-card\"]').forEach(el => el.remove())")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "keeps the revoke confirmation dialog accessible in both themes" do
    visit settings_sessions_path
    within("li", text: "Firefox on Windows") do
      click_button I18n.t("settings.sessions.index.revoke_button")
    end
    expect(page).to have_text(I18n.t("settings.sessions.index.revoke_title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "revokes another device and announces it" do
    visit settings_sessions_path
    within("li", text: "Firefox on Windows") do
      click_button I18n.t("settings.sessions.index.revoke_button")
    end
    within("dialog[open]") do
      click_button I18n.t("settings.sessions.index.revoke_button")
    end
    expect(page).to have_text(I18n.t("settings.sessions.destroy.signed_out", device: "Firefox on Windows"))
    within("ul[role='list']") do
      expect(page).not_to have_text("Firefox on Windows")
    end
  end
end
