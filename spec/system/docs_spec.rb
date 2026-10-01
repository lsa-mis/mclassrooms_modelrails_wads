require "rails_helper"

# System spec for the markdowndocs gem's templates as rendered inside this host
# app. The host's design tokens flip text/background colors when class="dark" is
# present on <html>; the gem's templates must keep up by pairing every light-mode
# Tailwind utility with a `dark:` variant. This spec is the canonical contrast
# judge — axe-core at WCAG 2.2 AAA in both color schemes.
RSpec.describe "Docs (markdowndocs gem)", type: :system do
  let(:axe_options) { AxeAccessibility::DEFAULT_AXE_OPTIONS.dup }

  describe "/docs/developer/getting-started" do
    it "renders the document" do
      visit "/docs/developer/getting-started"
      expect(page).to have_css("article", text: /Getting Started/i)
    end

    # Fenced code picks up the Rouge palette (_syntax.css). These audit the rendered page;
    # spec/code_smells/syntax_contrast_spec.rb holds every token to 7:1 on every ground.
    it "passes axe-core at WCAG 2.2 AAA in light mode (Rouge syntax tokens)" do
      visit "/docs/developer/getting-started"
      ensure_light_mode
      expect(axe_clean?(axe_options)).to be(true),
        "Light-mode AAA violations:\n#{axe_violations(axe_options).join("\n")}"
    end

    it "passes axe-core at WCAG 2.2 AAA in dark mode (Rouge syntax tokens)" do
      visit "/docs/developer/getting-started"
      ensure_dark_mode
      expect(axe_clean?(axe_options)).to be(true),
        "Dark-mode AAA violations:\n#{axe_violations(axe_options).join("\n")}"
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

    # The gem's docs-search controller matches a card by comparing the card's
    # `data-slug` against the ids in the search index, and the index is keyed on
    # the mode-prefixed path slug. A card tagged with the bare slug therefore
    # matches nothing and every card is hidden on any query (#1070,
    # markdowndocs#40). "timezone" was chosen by measuring the live filter: it is
    # the only term tried whose fuzzy neighbourhood is empty, so it narrows the
    # user-mode index to exactly one card.
    it "narrows the index cards to the documents matching the query" do
      visit "/docs"

      # The controller silently ignores a query typed before the index fetch
      # resolves, so synchronize on the response rather than on elapsed time.
      Timeout.timeout(Capybara.default_max_wait_time) do
        sleep 0.05 until cdp_browser.network.traffic.any? { |exchange|
          exchange.request.url.include?("search_index") && exchange.response
        }
      end
      expect(page).to have_link("Notifications")
      expect(page).to have_link("Welcome")

      # Located by placeholder: the control's accessible name is an `aria-label`
      # (UI::SearchInputComponent), which Capybara only matches with
      # `enable_aria_label`, and that is not set for this suite.
      fill_in I18n.t("markdowndocs.search_placeholder"), with: "timezone"

      # Order is load-bearing. The non-matching card is asserted FIRST because
      # its disappearance is what synchronizes on the debounced search having
      # run; asserting the matching card first passes against the pre-search
      # state, so both assertions sample different moments and prove nothing
      # (the #855 end-state trap, in miniature).
      expect(page).to have_no_link("Welcome")
      expect(page).to have_link("Notifications")
    end
  end
end
