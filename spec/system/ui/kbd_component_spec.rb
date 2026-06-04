# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility proof for the kbd component.
#
# kbd renders `text-text-muted` on `bg-surface-sunken`. In this token system
# text-text-muted resolves to the same neutral as text-text-body (de-emphasis
# comes from size/weight, not lightness), so the chip clears AAA 7:1 in both
# themes. This spec audits each scenario scoped to the <kbd> subtree with NO
# color-contrast exclude. NOTE: the per-spec assertion below runs axe's default
# (AA) rule set; the authoritative AAA 7:1 audit is the wcag2aaa after-hook that
# fires under CI (see spec/support/playwright_accessibility.rb).
#
# The preview-host minimal layout emits axe best-practice advisories
# (landmark-one-main, page-has-heading-one) that are NOT WCAG and NOT about the kbd,
# so we scope the audit to the <kbd> element rather than the whole page.
RSpec.describe "Kbd component accessibility", type: :system do
  %w[default combo in_context].each do |scenario|
    it "#{scenario} passes AAA in both themes" do
      visit "/rails/view_components/ui/kbd_component/#{scenario}"

      expect(page).to have_css("kbd")

      scope = [ "kbd" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
