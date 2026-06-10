# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the mega_menu component.
# A disclosure trigger (aria-haspopup/expanded/controls) revealing a named <nav> of
# link columns. Scoped to the mega-menu root (no color-contrast exclude).
RSpec.describe "Mega menu component accessibility", type: :system do
  %w[default].each do |scenario|
    it "#{scenario} renders a disclosure trigger and passes AAA in both themes" do
      visit "/rails/view_components/ui/mega_menu_component/#{scenario}"

      expect(page).to have_css("[data-controller='mega-menu'] button[aria-expanded]")

      scope = [ "[data-controller='mega-menu']" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
