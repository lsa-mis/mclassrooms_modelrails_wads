# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the stepper component.
# An <ol> progress indicator — the status circles (complete/current/pending) use
# signal/interactive tokens whose contrast is audited here. Scoped to the <ol>
# subtree (no color-contrast exclude), so a real contrast failure fails the spec.
RSpec.describe "Stepper component accessibility", type: :system do
  %w[default vertical].each do |scenario|
    it "#{scenario} renders an ordered progress list and passes AAA in both themes" do
      visit "/rails/view_components/ui/stepper_component/#{scenario}"

      expect(page).to have_css("ol")

      scope = [ "ol" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
