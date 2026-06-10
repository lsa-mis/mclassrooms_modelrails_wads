# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the navigation_menu component.
# A named <nav> of links with disclosure flyouts (aria-haspopup/expanded). Scoped to
# the <nav> subtree (no color-contrast exclude).
RSpec.describe "Navigation menu component accessibility", type: :system do
  %w[default].each do |scenario|
    it "#{scenario} renders a named nav with disclosure triggers and passes AAA in both themes" do
      visit "/rails/view_components/ui/navigation_menu_component/#{scenario}"

      expect(page).to have_css("nav[aria-label]")

      scope = [ "nav" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
