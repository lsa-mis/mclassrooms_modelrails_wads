# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility proof for the progress component.
#
# A determinate progress bar carries role="progressbar" with
# aria-valuenow/min/max, and an aria-label when no visible text names it. This
# spec asserts that structural contract on each scenario and audits each scoped to
# the [role='progressbar'] subtree with NO color-contrast exclude. NOTE: the
# per-spec assertion below runs axe's default (AA) rule set; the authoritative
# AAA 7:1 audit is the wcag2aaa after-hook that fires under CI (see
# spec/support/playwright_accessibility.rb).
RSpec.describe "Progress component accessibility", type: :system do
  it "default exposes valuenow/min/max and passes AAA in both themes" do
    visit "/rails/view_components/ui/progress_component/default"

    expect(page).to have_css(
      "[role='progressbar'][aria-valuenow='50'][aria-valuemin='0'][aria-valuemax='100']"
    )

    audit_progressbar
  end

  it "with_label exposes an aria-label and passes AAA in both themes" do
    visit "/rails/view_components/ui/progress_component/with_label"

    expect(page).to have_css("[role='progressbar'][aria-label='Upload']")

    audit_progressbar
  end

  it "complete reports valuenow=100 and passes AAA in both themes" do
    visit "/rails/view_components/ui/progress_component/complete"

    expect(page).to have_css("[role='progressbar'][aria-valuenow='100']")

    audit_progressbar
  end

  def audit_progressbar
    scope = [ "[role='progressbar']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
