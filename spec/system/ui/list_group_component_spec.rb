# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the list_group component.
#
# list_group renders a bare <ul> (no landmark role), so each preview wraps the
# list in #lg-scope and the audit is scoped there — keeping the host chrome's
# best-practice advisories (landmark-one-main, page-has-heading-one) out of
# scope WITHOUT excluding any rule. No color-contrast exclude: a real contrast
# failure on a row (including the filled active link, text-on-interactive on
# bg-interactive) would still fail this spec.
#
# The structural assertions hold the hardened contract: list children are always
# <li> (never bare anchors); link rows nest the <a> inside the <li>, carry the
# focus-ring outline, and the active link is aria-current="page".
RSpec.describe "ListGroup component accessibility", type: :system do
  # `let`, not a top-level constant (a constant inside describe leaks to ::SCOPE and
  # collides across scoped 0b specs → axe scopes to the wrong selector).
  let(:scope) { [ "#lg-scope" ] }

  it "default: renders a <ul> of <li> rows and passes AAA in both themes" do
    visit "/rails/view_components/ui/list_group_component/default"

    expect(page).to have_css("#lg-scope ul")
    expect(page).to have_css("#lg-scope ul > li", minimum: 2)
    # The selected row is a plain <li> (no href) — not a link in this scenario.
    expect(page).to have_no_css("#lg-scope ul > li > a")
    expect_aaa_in_both_themes(include: scope)
  end

  it "links: rows are li > a (not bare anchors), active is aria-current, links carry focus-ring; AAA in both themes" do
    visit "/rails/view_components/ui/list_group_component/links"

    # Children of the <ul> are <li> — never bare anchors (the structural fix).
    expect(page).to have_css("#lg-scope ul > li > a", count: 3)
    expect(page).to have_no_css("#lg-scope ul > a")

    # Exactly the active row's link is aria-current="page"; the others are not.
    expect(page).to have_css("#lg-scope ul > li > a[aria-current='page']", count: 1)

    # Every link carries the focus-ring outline.
    expect(page).to have_css("#lg-scope ul > li > a.focus-ring", count: 3)

    expect_aaa_in_both_themes(include: scope)
  end
end
