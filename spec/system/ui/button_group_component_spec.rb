# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the button_group component.
# A presentational role=group wrapper around segmented buttons. Scoped to the group
# subtree (no color-contrast exclude), so a real contrast failure on the buttons or
# their focus rings fails the spec.
RSpec.describe "Button group component accessibility", type: :system do
  %w[default].each do |scenario|
    it "#{scenario} renders a button group and passes AAA in both themes" do
      visit "/rails/view_components/ui/button_group_component/#{scenario}"

      expect(page).to have_css("[role='group']")

      scope = [ "[role='group']" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
