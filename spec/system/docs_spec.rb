require "rails_helper"

# System spec for the markdowndocs gem's templates as rendered inside this host
# app. The host's design tokens flip text/background colors when class="dark" is
# present on <html>; the gem's templates must keep up by pairing every light-mode
# Tailwind utility with a `dark:` variant. This spec is the canonical contrast
# judge — axe-core at WCAG 2.2 AAA in both color schemes.
RSpec.describe "Docs (markdowndocs gem)", type: :system do
  let(:axe_options) { PlaywrightAccessibility::DEFAULT_AXE_OPTIONS.dup }

  describe "/docs/developer/getting-started" do
    it "renders the document" do
      visit "/docs/developer/getting-started"
      expect(page).to have_css("article", text: /Getting Started/i)
    end

    # The show page renders user-authored Markdown that includes fenced code
    # blocks. Those code blocks pick up the host's Rouge syntax-highlighting
    # palette (--syntax-builtin, --syntax-comment, --syntax-name, --syntax-string,
    # --syntax-tag, etc.) declared in app/assets/tailwind/application.css.
    #
    # All foreground syntax tokens are tuned to clear WCAG 2.2 AAA (7:1) against
    # the surface background — L* ≤ 38% on light mode, L* ≥ 85% on dark mode.
    # The two specs below re-enable .highlight (Rouge syntax tokens) by passing
    # a narrowed `exclude:` that only filters out the biscuit GDPR banner —
    # itself separately deferred. They lock in the AAA token contract.
    it "passes axe-core at WCAG 2.2 AAA in light mode (Rouge syntax tokens)" do
      visit "/docs/developer/getting-started"
      ensure_light_mode
      expect(axe_clean?(axe_options, exclude: [ ".biscuit-banner" ])).to be(true),
        "Light-mode AAA violations:\n#{axe_violations(axe_options, exclude: [ ".biscuit-banner" ]).join("\n")}"
    end

    it "passes axe-core at WCAG 2.2 AAA in dark mode (Rouge syntax tokens)" do
      visit "/docs/developer/getting-started"
      ensure_dark_mode
      expect(axe_clean?(axe_options, exclude: [ ".biscuit-banner" ])).to be(true),
        "Dark-mode AAA violations:\n#{axe_violations(axe_options, exclude: [ ".biscuit-banner" ]).join("\n")}"
    end

    # The mobile sidebar uses a Stimulus action instead of inline onclick so it
    # works under our strict CSP (script-src :self with nonces, no
    # unsafe-inline). The gem's upstream template ships the inline-onclick
    # version; this assertion locks in the host override.
    # Region is `lg:hidden` so the elements are display:none at desktop test
    # viewport — assert against the DOM regardless of visibility.
    it "wires the mobile sidebar via Stimulus (CSP-safe toggle)" do
      visit "/docs/developer/getting-started"
      expect(page).to have_css('[data-controller="docs-sidebar"]', visible: :all)
      expect(page).to have_css('button[data-action="docs-sidebar#toggle"]', visible: :all)
      expect(page).to have_css('[data-docs-sidebar-target="sidebar"]', visible: :all)
      expect(page).to have_css('[data-docs-sidebar-target="iconOpen"]', visible: :all)
      expect(page).to have_css('[data-docs-sidebar-target="iconClose"]', visible: :all)
    end
  end

  describe "/docs (index)" do
    it "renders the index" do
      visit "/docs"
      expect(page).to have_text(/Documentation/i)
    end

    it "passes axe-core at WCAG 2.2 AAA in light mode" do
      visit "/docs"
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end
end
