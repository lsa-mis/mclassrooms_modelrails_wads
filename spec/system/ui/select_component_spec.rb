# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility proof for the customizable-select picker styling
# (`@supports (appearance: base-select)`). In supporting browsers (our Playwright
# Chromium ≥ 130) `.ui-select` renders a fully styled picker in the top layer; we
# OPEN it via a real click and audit the LIVE options, since a closed picker's
# options are not rendered (axe would skip them).
#
# NOTE: the per-spec axe call runs axe's default (AA) rule set; the authoritative
# AAA 7:1 audit is the CI-only wcag2aaa after-hook (spec/support/axe_accessibility.rb).
RSpec.describe "Select component accessibility", type: :system do
  it "opens a styled picker that passes AAA in both themes" do
    visit "/rails/view_components/ui/select_component/selected"

    expect(page).to have_css("select.ui-select")

    # Open the customizable-select picker (top layer) so the styled options are live.
    # Assert the `:open` state explicitly — otherwise a future regression where the
    # click no longer opens the picker would silently audit a closed (empty) control.
    find("select.ui-select").click
    expect(page).to have_css("select.ui-select:open")
    expect(page).to have_css("select.ui-select option", visible: true, minimum: 1)

    scope = [ "select.ui-select" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
