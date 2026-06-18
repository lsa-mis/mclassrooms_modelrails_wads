require "rails_helper"

RSpec.describe "Account Appearance destination", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before { sign_in_via_form(user) }

  it "renders the Appearance H1 (sidebar label parity)" do
    visit edit_settings_theme_preference_path
    expect(page).to have_css("h1", text: I18n.t("settings.pages.appearance.h1"))
  end

  it "renders the Appearance description" do
    visit edit_settings_theme_preference_path
    expect(page).to have_text(I18n.t("settings.pages.appearance.description"))
  end

  it "passes axe-core at WCAG 2.2 AAA in light and dark modes" do
    visit edit_settings_theme_preference_path
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
