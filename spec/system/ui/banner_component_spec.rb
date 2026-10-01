# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the banner component.
#
# banner renders `<div role="region">` (a findable/skippable landmark), so axe scopes
# by that role — no wrapper needed. NO color-contrast exclude: this proves the tinted
# signal treatment (bg-*-surface + text-* + *-border) clears AAA 7:1 in BOTH themes —
# the raw-palette the hardening replaced (bg-blue-50/text-blue-900…) would fail here.
RSpec.describe "Banner component accessibility", type: :system do
  # `let`, not a top-level constant (a constant inside describe leaks to ::SCOPE and
  # collides across scoped 0b specs → axe scopes to the wrong selector).
  let(:scope) { [ "[role='region']" ] }

  it "default: renders a region landmark and passes AAA in both themes" do
    visit "/rails/view_components/ui/banner_component/default"

    expect(page).to have_css("[role='region']")
    expect_aaa_in_both_themes(include: scope)
  end

  it "info: the tinted info surface passes AAA in both themes" do
    visit "/rails/view_components/ui/banner_component/info"

    expect(page).to have_css("[role='region']")
    expect_aaa_in_both_themes(include: scope)
  end

  it "dismissible: the close button has an accessible name + focus-ring; AAA in both themes" do
    visit "/rails/view_components/ui/banner_component/dismissible"

    expect(page).to have_css("[role='region'] button[aria-label].focus-ring")
    expect_aaa_in_both_themes(include: scope)
  end

  it "showcase renders every variant and passes AAA in both themes" do
    visit "/rails/view_components/ui/banner_component/showcase"

    expect(page).to have_css("[data-showcase=banner]", minimum: 1)
    scope = [ "[data-showcase=banner]" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
