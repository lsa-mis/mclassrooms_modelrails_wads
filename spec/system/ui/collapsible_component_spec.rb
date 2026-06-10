# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the collapsible component.
# Native <details>/<summary> — the summary is the focusable disclosure control
# carrying the AAA `focus-ring`. Scoped to the <details> subtree (no color-contrast
# exclude), so a real contrast failure on the summary or visible content fails here.
RSpec.describe "Collapsible component accessibility", type: :system do
  %w[default expanded].each do |scenario|
    it "#{scenario} renders a disclosure and passes AAA in both themes" do
      visit "/rails/view_components/ui/collapsible_component/#{scenario}"

      expect(page).to have_css("details summary")

      scope = [ "details" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
