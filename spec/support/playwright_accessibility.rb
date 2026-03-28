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
      options = { runOnly: { type: "tag", values: ["wcag2aa"] } }
      expect(axe_clean?(options)).to be(true),
        "Accessibility violations found:\n#{axe_violations(options).join("\n")}"
    end
  end
end
