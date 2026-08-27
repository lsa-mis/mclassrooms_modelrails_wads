require "rails_helper"

RSpec.describe "Re-authentication interstitial", type: :system do
  let(:user) { create(:user, :passwordless, first_name: "Rae", last_name: "Auth") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    sign_in_via_form(user)
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
