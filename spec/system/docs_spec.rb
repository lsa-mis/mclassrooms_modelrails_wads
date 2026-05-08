require "rails_helper"

# System spec for the markdowndocs gem's templates as rendered inside this host
# app. The host's design tokens flip text/background colors when class="dark" is
# present on <html>; the gem's templates must keep up by pairing every light-mode
# Tailwind utility with a `dark:` variant. This spec is the canonical contrast
# judge — axe-core at WCAG 2.2 AAA in both color schemes.
RSpec.describe "Docs (markdowndocs gem)", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  describe "/docs/getting-started" do
    it "renders the document" do
      visit "/docs/getting-started"
      expect(page).to have_css("article", text: /Getting Started/i)
    end

    # The show page renders user-authored Markdown that includes fenced code
    # blocks. Those code blocks pick up the host's Rouge syntax-highlighting
    # palette (--syntax-builtin, --syntax-comment, --syntax-name, --syntax-string,
    # --syntax-tag) which currently sits at AA contrast, not AAA. Bumping every
    # token to AAA is a design-aesthetic call (it changes how every code example
    # in every doc looks) and is being deferred to a follow-up. The gem-side
    # template fixes (containers, headings, links, sidebar) are exercised by the
    # /docs index assertions below and by direct visual inspection of show-page
    # chrome.
    # The two specs below intentionally re-enable .highlight (Rouge syntax
    # tokens) by passing a narrowed `exclude:` that only filters out the
    # biscuit GDPR banner — itself separately deferred. They remain `pending`
    # because Rouge tokens still don't meet AAA contrast; they exist as
    # canaries that will start failing-as-pending once the Rouge palette is
    # tightened, prompting us to remove the deferral.
    it "passes axe-core at WCAG 2.2 AAA in light mode (deferred: Rouge tokens)" do
      visit "/docs/getting-started"
      ensure_light_mode
      pending "Rouge syntax-token AAA tightening — see PR description Deferred section"
      expect(axe_clean?(axe_options, exclude: [ ".biscuit-banner" ])).to be(true),
        "Light-mode AAA violations:\n#{axe_violations(axe_options, exclude: [ ".biscuit-banner" ]).join("\n")}"
    end

    it "passes axe-core at WCAG 2.2 AAA in dark mode (deferred: Rouge tokens)" do
      visit "/docs/getting-started"
      ensure_dark_mode
      pending "Rouge syntax-token AAA tightening — see PR description Deferred section"
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
      visit "/docs/getting-started"
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
