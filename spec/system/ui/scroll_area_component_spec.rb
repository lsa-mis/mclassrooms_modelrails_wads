# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the scroll_area component.
#
# A focusable scroll_area renders `<div role="region" tabindex="0">` with an
# accessible name (the WCAG 2.1.1 keyboard fix: a bounded scroll box must be a
# named, reachable tab stop so keyboard-only users can focus it and arrow-scroll,
# and AT announces what scrolls). axe scopes by that role — no wrapper needed.
#
# NO color-contrast exclude: this proves the region's `focus-ring` indicator and
# token-driven body text (text-text-body on the themed surface) clear AAA 7:1 in
# BOTH themes. The `dont_no_keyboard_access` scenario uses `focusable: false`, so
# it renders no region (the intentional anti-pattern) and is excluded from the audit.
RSpec.describe "ScrollArea component accessibility", type: :system do
  # `let`, NOT a top-level constant: a constant assigned inside an RSpec.describe
  # block leaks to ::SCOPE, so multiple scoped 0b specs would clobber each other and
  # axe would scope to the wrong selector ("No elements found for include").
  let(:scope) { [ "[role='region']" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "default: the vertical region is a named, focus-ringed tab stop and passes AAA in both themes" do
    visit "/rails/view_components/ui/scroll_area_component/default"

    expect(page).to have_css("[role='region'][tabindex='0'][aria-label].focus-ring")
    expect_aaa_in_both_themes
  end

  it "horizontal: the horizontal region is a named, focus-ringed tab stop and passes AAA in both themes" do
    visit "/rails/view_components/ui/scroll_area_component/horizontal"

    expect(page).to have_css("[role='region'][tabindex='0'][aria-label].focus-ring")
    expect_aaa_in_both_themes
  end
end
