# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility proof for the indicator component.
#
# An indicator is a presentational corner dot/count anchored to another element;
# it conveys nothing on its own to AT (the anchored element carries the accessible
# name). This spec asserts the wrapper structure, the count text, and the AAA
# variant treatments, then audits each scenario scoped to the indicator wrapper
# (span.relative) with NO color-contrast exclude. NOTE: the per-spec assertion
# below runs axe's default (AA) rule set; the authoritative AAA 7:1 audit is the
# wcag2aaa after-hook that fires under CI (see
# spec/support/playwright_accessibility.rb).
RSpec.describe "Indicator component accessibility", type: :system do
  it "default renders the wrapper and passes AAA in both themes" do
    visit "/rails/view_components/ui/indicator_component/default"

    expect(page).to have_css("span.relative")

    audit_indicator
  end

  it "with_count shows the count and passes AAA in both themes" do
    visit "/rails/view_components/ui/indicator_component/with_count"

    expect(page).to have_css("span.relative")
    expect(page).to have_css("span.absolute", text: "3")

    audit_indicator
  end

  it "variants carry success/warning/danger dots and pass AAA in both themes" do
    visit "/rails/view_components/ui/indicator_component/variants"

    expect(page).to have_css("span.bg-success")
    expect(page).to have_css("span.bg-warning")
    expect(page).to have_css("span.bg-danger")

    audit_indicator
  end

  def audit_indicator
    scope = [ "span.relative" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
