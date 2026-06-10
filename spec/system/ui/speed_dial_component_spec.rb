# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the speed_dial component.
# A FAB disclosure: the trigger carries the focus-ring + aria-expanded; actions are
# revealed on open. Scoped to the speed-dial root (no color-contrast exclude).
RSpec.describe "Speed dial component accessibility", type: :system do
  %w[default].each do |scenario|
    it "#{scenario} renders a labelled FAB and passes AAA in both themes" do
      visit "/rails/view_components/ui/speed_dial_component/#{scenario}"

      expect(page).to have_css("[data-controller='speed-dial'] button")

      scope = [ "[data-controller='speed-dial']" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
