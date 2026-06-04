# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility proof for the spinner component.
#
# A spinner signals an indeterminate wait: it carries role="status" plus an
# sr-only loading label (i18n, English default "Loading…") so the spin is
# announced rather than silent. This spec asserts that structural contract on each
# scenario and audits each scoped to the [role='status'] subtree with NO
# color-contrast exclude. NOTE: the per-spec assertion below runs axe's default
# (AA) rule set; the authoritative AAA 7:1 audit is the wcag2aaa after-hook that
# fires under CI (see spec/support/playwright_accessibility.rb).
RSpec.describe "Spinner component accessibility", type: :system do
  %w[default sizes on_surface].each do |scenario|
    it "#{scenario} has role=status with an sr-only label and passes AAA in both themes" do
      visit "/rails/view_components/ui/spinner_component/#{scenario}"

      expect(page).to have_css("[role='status'] .sr-only", text: "Loading…")

      scope = [ "[role='status']" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
