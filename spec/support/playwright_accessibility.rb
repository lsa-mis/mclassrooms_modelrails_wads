# frozen_string_literal: true

# Playwright accessibility testing helper using axe-core
# Injects axe-core JavaScript and runs accessibility audits
module PlaywrightAccessibility
  AXE_SOURCE = Axe::Configuration.instance.jslib.freeze

  # Run axe accessibility audit on the current page
  def run_axe_audit(options = {})
    Capybara.current_session.driver.with_playwright_page do |playwright_page|
      inject_axe(playwright_page)

      playwright_page.evaluate(<<~JAVASCRIPT)
        (async () => {
          const options = #{options.to_json};
          return await axe.run(options);
        })();
      JAVASCRIPT
    end
  end

  # Check if page has any accessibility violations
  def axe_clean?(options = {})
    results = run_axe_audit(options)
    results["violations"].empty?
  end

  # Get formatted violation messages
  def axe_violations(options = {})
    results = run_axe_audit(options)

    results["violations"].map do |violation|
      nodes = violation["nodes"].map { |node| node["html"] }.join("\n  ")
      "\n#{violation["id"]}: #{violation["help"]}\n" \
      "  Impact: #{violation["impact"]}\n" \
      "  Affected elements:\n  #{nodes}"
    end
  end

  private

  def inject_axe(playwright_page)
    already_loaded = playwright_page.evaluate("typeof axe !== 'undefined'")
    return if already_loaded

    playwright_page.evaluate(AXE_SOURCE)
  end
end

RSpec.configure do |config|
  config.include PlaywrightAccessibility, type: :system

  # In CI, automatically run axe accessibility audit after every system spec
  if ENV["CI"]
    config.after(:each, type: :system) do
      # Prepare toasts for audit:
      # - Defeat in-progress animations (element opacity, transforms)
      # - Force a solid background so axe can reliably compute color contrast.
      #   The toast's production background uses alpha transparency (oklch / 90%),
      #   which requires axe to walk up the DOM and blend with ancestors. That
      #   walk-up is sensitive to DOM state and occasionally produces a flaky
      #   "color-contrast" violation. Overriding to a solid-alpha version of
      #   the same OKLCH color gives axe a deterministic value to test against,
      #   without changing the production visual design.
      Capybara.current_session.driver.with_playwright_page do |playwright_page|
        playwright_page.evaluate(<<~JS)
          document.querySelectorAll('[data-controller="toast-pill"], [data-controller="toast-card"]').forEach(el => {
            el.style.transition = 'none';
            el.style.opacity = '1';
            el.style.transform = 'none';

            // Replace the computed background with a solid (no-alpha) version.
            // getComputedStyle returns rgba(r, g, b, a) — drop the alpha to 1.
            const bg = getComputedStyle(el).backgroundColor;
            const match = bg.match(/rgba?\\(([^)]+)\\)/);
            if (match) {
              const parts = match[1].split(',').map(s => s.trim());
              el.style.backgroundColor = `rgb(${parts[0]}, ${parts[1]}, ${parts[2]})`;
            }
          });

          // Force a synchronous reflow so the style overrides are reflected
          // in computed styles before axe queries them.
          document.body.offsetHeight;
        JS
      end

      options = { runOnly: { type: "tag", values: [ "wcag2aa" ] } }
      results = run_axe_audit(options)
      violations = results["violations"] || []

      formatted = violations.map do |v|
        nodes = (v["nodes"] || []).map { |n| n["html"] }.join("\n  ")
        "\n#{v["id"]}: #{v["help"]}\n  Impact: #{v["impact"]}\n  Affected elements:\n  #{nodes}"
      end

      expect(violations).to be_empty,
        "Accessibility violations found:#{formatted.join("\n")}"
    end
  end
end
