# frozen_string_literal: true

require "rails_helper"

# A skeleton is decorative, so aria-hidden + motion-safe:animate-pulse is its whole contract and the
# structural asserts are the proof: axe skips aria-hidden subtrees, and the AAA audit is the teardown hook.
RSpec.describe "Skeleton component accessibility", type: :system do
  %w[default card circle].each do |scenario|
    it "#{scenario} is aria-hidden, pulses, and respects reduced motion" do
      visit "/rails/view_components/ui/skeleton_component/#{scenario}"

      expect(page).to have_css("[aria-hidden='true'].motion-safe\\:animate-pulse")
      expect(page).to have_no_css("[aria-hidden='true'].animate-pulse")
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
