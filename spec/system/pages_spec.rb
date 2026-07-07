require "rails_helper"

RSpec.describe "Public marketing pages", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  describe "landing page" do
    before do
      # The primary CTA is gated on signups_open? (SignupPolicy). Stub the
      # instance to :open so the anonymous-visitor CTA is deterministic,
      # matching spec/system/static_pages_spec.rb's existing convention —
      # the underlying signup posture is out of scope for brand seams.
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
      visit root_path
    end

    it "shows the anonymous visitor a sign-in call-to-action" do
      expect(page).to have_link(I18n.t("pages.home.hero.cta_primary"), href: new_session_path)
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
