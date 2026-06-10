# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the sidebar component.
# An <aside> rail with a named <nav> landmark; toggle + items carry the focus-ring.
# Scoped to the <aside> subtree (no color-contrast exclude).
RSpec.describe "Sidebar component accessibility", type: :system do
  %w[default collapsed].each do |scenario|
    it "#{scenario} renders a named-nav rail and passes AAA in both themes" do
      visit "/rails/view_components/ui/sidebar_component/#{scenario}"

      expect(page).to have_css("aside nav[aria-label]")

      scope = [ "aside" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
