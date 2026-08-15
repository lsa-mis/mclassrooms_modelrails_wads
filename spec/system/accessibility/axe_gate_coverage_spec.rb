# frozen_string_literal: true

require "rails_helper"

# Harness self-test: proves the axe gate's default option set selects the full
# cumulative WCAG A/AA/AAA rule stack. axe's `runOnly` tags are NOT
# cumulative — passing only "wcag2aaa" selects just the 3 AAA-tagged rules and
# silently skips the whole A/AA foundation (labels, alt text, names, titles).
# Exactly that regression shipped once (fixed in the #540–#542 arc); this spec
# exists so it can never happen silently again.
#
# It injects a deliberately broken element instead of visiting a real broken
# page — the subject under test is the audit harness itself, not app UI, so
# the project rule "system specs test real rendered HTML" does not apply.
RSpec.describe "axe gate rule coverage", type: :system do
  it "selects the full A/AA/AAA rule stack, not just AAA-tagged rules" do
    visit root_path
    inject_axe

    rule_ids = page.evaluate_script(
      "axe.getRules(#{PlaywrightAccessibility::AXE_TAG_SET.to_json}).map(r => r.ruleId)"
    )

    expect(rule_ids).to include(
      "label", "image-alt", "link-name", "button-name", "document-title",
      "html-has-lang", "target-size", "color-contrast-enhanced"
    )
    expect(rule_ids.length).to be > 40
  end

  it "catches a seeded unlabeled input under the gate's default options" do
    visit root_path
    page.execute_script(<<~JS)
      document.body.insertAdjacentHTML(
        "beforeend", '<input id="a11y-gate-probe" type="text">'
      )
    JS

    results = run_axe_audit(exclude: [], include: "#a11y-gate-probe")

    expect(results["violations"].map { |v| v["id"] }).to include("label")
  ensure
    # The CI after-hook re-audits the page (both themes), so the deliberately
    # broken probe must not leak into it.
    page.execute_script('document.getElementById("a11y-gate-probe")?.remove()')
  end
end
