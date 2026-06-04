# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility proof for the separator component.
#
# The decorative default carries role="none" with NO aria-orientation (which is
# invalid on role="none"); the semantic variant carries role="separator" with an
# explicit aria-orientation. This spec asserts that structural contract and audits
# the SEMANTIC scenario scoped to the [role='separator'] subtree with NO
# color-contrast exclude. NOTE: the per-spec assertion below runs axe's default
# (AA) rule set; the authoritative AAA 7:1 audit is the wcag2aaa after-hook that
# fires under CI (see spec/support/playwright_accessibility.rb).
#
# The default/vertical decorative scenarios have no text and no role, so only their
# structure is asserted (no axe audit needed for a no-text decorative rule).
RSpec.describe "Separator component accessibility", type: :system do
  it "default is decorative role=none with no aria-orientation" do
    visit "/rails/view_components/ui/separator_component/default"

    expect(page).to have_css("div[role='none']")
    expect(page).to have_no_css("div[role='none'][aria-orientation]")
  end

  it "vertical renders" do
    visit "/rails/view_components/ui/separator_component/vertical"

    expect(page).to have_css("div[role]")
  end

  it "semantic has role=separator with aria-orientation and passes AAA in both themes" do
    visit "/rails/view_components/ui/separator_component/semantic"

    expect(page).to have_css("div[role='separator'][aria-orientation='horizontal']")

    scope = [ "[role='separator']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
