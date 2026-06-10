# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the bottom_nav component.
# A named <nav> bar of links with focus-ring + aria-current. Scoped to the <nav>
# subtree (no color-contrast exclude).
RSpec.describe "Bottom nav component accessibility", type: :system do
  %w[default].each do |scenario|
    it "#{scenario} renders a named nav bar and passes AAA in both themes" do
      visit "/rails/view_components/ui/bottom_nav_component/#{scenario}"

      expect(page).to have_css("nav[aria-label]")

      scope = [ "nav" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
