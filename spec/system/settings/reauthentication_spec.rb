require "rails_helper"

RSpec.describe "Re-authentication interstitial", type: :system do
  let(:user) { create(:user, :passwordless, first_name: "Rae", last_name: "Auth") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    token = MagicLinkToken.create_for_email(user.email_address)
    visit magic_link_callback_path(token: token)
    click_button I18n.t("magic_link_callbacks.confirm.sign_in_button")
    expect(page).to have_css("#user-menu-button")
  end

  it "renders the interstitial accessibly in both themes (passwordless: email factor)" do
    visit new_settings_reauthentication_path
    expect(page).to have_text(I18n.t("settings.reauthentications.new.title"))
    expect(page).to have_button(I18n.t("settings.reauthentications.new.email_button"))
    expect(page).not_to have_field(I18n.t("settings.reauthentications.new.password_label"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "emails a code and shows the code-entry field accessibly in both themes" do
    visit new_settings_reauthentication_path
    click_button I18n.t("settings.reauthentications.new.email_button")
    expect(page).to have_field(I18n.t("settings.reauthentications.new.code_label"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
