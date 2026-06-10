# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the toggle_group component.
# A named role=group of toggle buttons (aria-pressed). Scoped to the group subtree
# (no color-contrast exclude), so a real contrast failure on a toggle in either its
# pressed or unpressed state fails the spec.
RSpec.describe "Toggle group component accessibility", type: :system do
  %w[default multiple].each do |scenario|
    it "#{scenario} renders a labelled toggle group and passes AAA in both themes" do
      visit "/rails/view_components/ui/toggle_group_component/#{scenario}"

      expect(page).to have_css("[role='group'][aria-label]")

      scope = [ "[role='group']" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
