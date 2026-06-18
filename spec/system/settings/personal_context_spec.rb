require "rails_helper"

RSpec.describe "Settings hub — personal context", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:sidebar_selector) { "aside[aria-label='#{I18n.t("settings.sidebar.aria_label")}']" }

  before { sign_in_via_form(user) }

  it "renders the personal-context sidebar with all user-tier items" do
    visit edit_settings_profile_path

    within(sidebar_selector) do
      expect(page).to have_link(I18n.t("settings.sidebar.items.profile"))
      expect(page).to have_link(I18n.t("settings.sidebar.items.notifications"))
      expect(page).to have_link(I18n.t("settings.sidebar.items.security"))
      expect(page).to have_link(I18n.t("settings.sidebar.items.appearance"))

      expect(page).not_to have_link(I18n.t("settings.sidebar.items.members"))
      expect(page).not_to have_link(I18n.t("settings.sidebar.items.invitations"))
      expect(page).not_to have_link(I18n.t("settings.sidebar.items.limits_and_plan"))
    end
  end

  it "exposes the personal context via data attribute" do
    visit edit_settings_profile_path
    expect(page).to have_css("[data-workspace-kind='personal']")
  end

  it "marks the current page in the sidebar with aria-current" do
    visit edit_settings_profile_path
    within(sidebar_selector) do
      expect(page).to have_css(
        "a[aria-current='page']",
        text: I18n.t("settings.sidebar.items.profile")
      )
    end
  end

  it "passes axe-core at WCAG 2.2 AAA in light and dark modes" do
    visit edit_settings_profile_path

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
