require "rails_helper"

RSpec.describe "Public marketing pages", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  describe "landing page" do
    # Deliberately NO signup-mode stub: the sign-in CTAs must render under
    # the REAL default config (SIGNUP_MODE=invite_only). In this codebase
    # sign-IN is unconditional and only sign-UP is gated by signups_open?
    # (see the header partial) — the landing page follows the same
    # convention, so its CTAs must never vanish for anonymous visitors.
    before { visit root_path }

    # Scoped to main#main-content: the header ALSO carries an unconditional
    # "Sign in" link with the same text and href, so an unscoped have_link
    # would pass even if the landing page's own CTAs vanished.
    it "shows the anonymous visitor a sign-in call-to-action under default config" do
      within("main#main-content") do
        expect(page).to have_link(I18n.t("pages.home.hero.cta_primary"), href: new_session_path)
      end
    end

    it "shows the bottom sign-in call-to-action under default config" do
      within("main#main-content") do
        expect(page).to have_link(I18n.t("pages.home.cta.button"), href: new_session_path)
      end
    end

    it "carries no leftover template branding" do
      expect(page).not_to have_text("ModelRails")
    end

    it "lets the anonymous visitor reach the About page" do
      click_link I18n.t("pages.home.hero.cta_secondary"), href: about_path
      expect(page).to have_current_path(about_path)
      expect(page).to have_text(I18n.t("pages.about.hero.title"))
    end

    it "passes automated accessibility checks at WCAG AAA (light + dark)" do
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  describe "about page" do
    before { visit about_path }

    it "carries no leftover template branding" do
      expect(page).not_to have_text("ModelRails")
    end

    it "passes automated accessibility checks at WCAG AAA (light + dark)" do
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end
end
