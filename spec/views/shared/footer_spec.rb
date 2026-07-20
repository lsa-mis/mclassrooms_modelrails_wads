require "rails_helper"

RSpec.describe "shared/_footer", type: :view do
  before { render "shared/footer" }

  describe "structure" do
    it "renders a footer landmark" do
      expect(rendered).to have_css("footer")
    end

    it "renders the site logo link to root" do
      expect(rendered).to have_css("a[href='/']")
    end

    it "renders a centered copyright row with the current year" do
      expect(rendered).to have_css("p.text-center", text: Date.current.year.to_s)
      expect(rendered).to have_css("p.text-center", text: I18n.t("footer.copyright"))
    end

    it "includes an aria-hidden vertical divider between nav clusters" do
      expect(rendered).to have_css("div.border-l.border-border[aria-hidden='true']", visible: :all)
    end

    it "includes a horizontal rule divider between the two rows" do
      expect(rendered).to have_css("div.border-t.border-border")
    end

    it "mounts the footer Stimulus controller on the footer element" do
      expect(rendered).to have_css("footer[data-controller='footer']")
    end
  end

  describe "Product cluster" do
    let(:selector) { "nav[aria-label='#{I18n.t('footer.aria.product')}']" }

    it "is a nav landmark with the correct aria-label" do
      expect(rendered).to have_css(selector)
    end

    it "contains the About link" do
      expect(rendered).to have_css("#{selector} a", text: I18n.t("footer.about"))
    end

    it "contains the Docs link" do
      expect(rendered).to have_css("#{selector} a", text: I18n.t("footer.docs"))
    end
  end

  describe "Legal cluster" do
    let(:selector) { "nav[aria-label='#{I18n.t('footer.aria.legal')}']" }

    it "is a nav landmark with the correct aria-label" do
      expect(rendered).to have_css(selector)
    end

    it "contains the Privacy link" do
      expect(rendered).to have_css("#{selector} a", text: I18n.t("footer.privacy"))
    end

    it "contains the Contact link" do
      expect(rendered).to have_css("#{selector} a", text: I18n.t("footer.contact"))
    end

    it "contains a Cookie settings button wired to footer#reopenCookies" do
      expect(rendered).to have_css(
        "#{selector} button[data-action*='click->footer#reopenCookies']",
        text: I18n.t("footer.cookie_settings")
      )
    end

    it "gives the Cookie settings button an accessible label and does not promise a dialog" do
      expect(rendered).to have_css(
        "#{selector} button[data-action*='click->footer#reopenCookies']",
        text: I18n.t("footer.cookie_settings")
      )
      expect(rendered).not_to have_css(
        "#{selector} button[aria-haspopup='dialog']"
      )
    end

    it "meets AAA target-size by applying --form-input-height to interactive elements" do
      # Reads --form-input-height token (Design System Primitives v2 sweep)
      expect(rendered).to have_css("#{selector} a.min-h-\\[var\\(--form-input-height\\)\\]", count: 2)
      expect(rendered).to have_css("#{selector} button.min-h-\\[var\\(--form-input-height\\)\\]", count: 1)
    end
  end
end
