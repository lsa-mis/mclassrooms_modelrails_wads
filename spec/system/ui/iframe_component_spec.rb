# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the iframe component.
#
# An iframe carries no landmark/live-region role to scope by, so each preview
# wraps the frame in `#if-scope` and axe audits the COMPONENT subtree, not the
# host chrome (the minimal preview layout emits best-practice advisories like
# landmark-one-main that are not WCAG and not about the iframe).
#
# The key a11y fix this hardening proves: every rendered iframe carries a
# non-blank `title` (its accessible name) — a title-less iframe is a hard WCAG
# failure and the component fails loud rather than render one. No color-contrast
# exclude, so the `dont_no_title` sample's AAA tokens (`text-text-body` on
# `bg-surface-sunken`) are proven in BOTH themes too.
RSpec.describe "Iframe component accessibility", type: :system do
  # `let`, NOT a top-level constant: a constant assigned inside an RSpec.describe
  # block leaks to ::SCOPE, so multiple scoped 0b specs would clobber each other and
  # axe would scope to the wrong selector ("No elements found for include").
  let(:scope) { [ "#if-scope" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "default: renders a titled iframe and passes AAA in both themes" do
    visit "/rails/view_components/ui/iframe_component/default"

    expect(page).to have_css("#if-scope iframe[title='Map of central London']")
    expect_aaa_in_both_themes
  end

  it "responsive: renders an aspect-constrained titled iframe and passes AAA in both themes" do
    visit "/rails/view_components/ui/iframe_component/responsive"

    expect(page).to have_css("#if-scope iframe[title='Product demo video']")
    expect_aaa_in_both_themes
  end

  # skip_axe_hook: this preview DELIBERATELY renders the anti-pattern (a
  # title-less iframe) to document it — the CI after-each audit would
  # rightly fail it, which is the point of the example, not a regression.
  it "dont_no_title: documents the failure mode with no live title-less iframe", skip_axe_hook: true do
    visit "/rails/view_components/ui/iframe_component/dont_no_title"

    # The "don't" scenario documents the failure mode via a non-executing <pre>
    # sample (the component fails loud on a blank title) — assert it renders no
    # actual title-less iframe. No axe pass here: the audit target is the iframe's
    # accessible name, and the only element on this page is a scrollable doc <pre>
    # whose scrollable-region-focusable advisory is unrelated to the component.
    expect(page).to have_no_css("#if-scope iframe")
  end
end
