# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility proof for the skeleton component.
#
# A skeleton is a purely decorative loading placeholder: it carries
# aria-hidden="true" (so AT never announces a series of empty boxes) and
# animate-pulse / motion-reduce:animate-none (the pulse is suppressed for
# reduced-motion users). This spec asserts that structural contract on each
# scenario and audits the default scoped to the [aria-hidden='true'] subtree.
# axe skips aria-hidden subtrees, so a clean audit there confirms nothing bubbles
# out of the placeholder — the structural asserts are the real proof for a
# decorative element. NOTE: the per-spec assertion below runs axe's default (AA)
# rule set; the authoritative AAA 7:1 audit is the wcag2aaa after-hook that fires
# under CI (see spec/support/playwright_accessibility.rb).
RSpec.describe "Skeleton component accessibility", type: :system do
  %w[default card circle].each do |scenario|
    it "#{scenario} is aria-hidden, pulses, and respects reduced motion" do
      visit "/rails/view_components/ui/skeleton_component/#{scenario}"

      expect(page).to have_css("[aria-hidden='true'].animate-pulse")
      expect(page).to have_css("[aria-hidden='true'].motion-reduce\\:animate-none")
    end
  end

  it "default passes AAA in both themes" do
    visit "/rails/view_components/ui/skeleton_component/default"

    scope = [ "[aria-hidden='true']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
