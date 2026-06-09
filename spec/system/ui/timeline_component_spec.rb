# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the timeline component.
#
# Timeline renders a semantic ordered list (`<ol>` of `<li>`) with no landmark
# role, so there is nothing to scope axe by on its own. Each preview wraps the
# timeline in `#tl-scope` so the audit covers the COMPONENT subtree, not the
# host chrome (the minimal preview layout emits best-practice advisories like
# landmark-one-main that are not WCAG and not about the timeline).
#
# No color-contrast exclude — a real contrast failure on the marker dots
# (semantic signal fills) or the muted `<time>` label would still fail this
# spec, proving the AAA `bg-info`/`bg-success`/`bg-warning`/`bg-danger` dots and
# the `text-text-muted` date tokens in BOTH themes.
RSpec.describe "Timeline component accessibility", type: :system do
  # `let`, NOT a top-level constant: a constant assigned inside an RSpec.describe
  # block leaks to ::SCOPE, so multiple scoped 0b specs would clobber each other
  # and axe would scope to the wrong selector ("No elements found for include").
  let(:scope) { [ "#tl-scope" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "default: renders an ordered sequence of events and passes AAA in both themes" do
    visit "/rails/view_components/ui/timeline_component/default"

    expect(page).to have_css("#tl-scope ol > li", count: 3)
    expect(page).to have_css("#tl-scope ol > li", text: "Project kickoff")
    expect(page).to have_css("#tl-scope ol > li", text: "v1.0 launched")
    expect_aaa_in_both_themes
  end

  it "variants: renders semantic signal dots along the sequence and passes AAA in both themes" do
    visit "/rails/view_components/ui/timeline_component/variants"

    expect(page).to have_css("#tl-scope ol > li", count: 4)
    expect(page).to have_css("#tl-scope ol > li", text: "Tests passed")
    expect(page).to have_css("#tl-scope ol > li", text: "Deploy failed")
    expect_aaa_in_both_themes
  end

  it "with_datetime: renders machine-readable <time datetime> and passes AAA in both themes" do
    visit "/rails/view_components/ui/timeline_component/with_datetime"

    expect(page).to have_css("#tl-scope ol > li", count: 3)
    expect(page).to have_css("#tl-scope time[datetime]", count: 3)
    expect(page).to have_css("#tl-scope time[datetime='2025-01']")
    expect_aaa_in_both_themes
  end
end
