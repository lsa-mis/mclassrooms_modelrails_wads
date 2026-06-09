# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the picture component.
#
# Picture is a roleless presentational element (a plain `<picture>` wrapping
# `<source>`s and a base `<img>`), so there is no live-region role to scope by.
# Each preview wraps the picture in `#pic-scope` so axe audits the COMPONENT
# subtree, not the host chrome (the minimal preview layout emits best-practice
# advisories like landmark-one-main that are not WCAG and not about the picture).
#
# The KEY a11y contract: the base `<img>` carries the accessible name (`alt`);
# `<source>`s never do. Each scenario asserts at least one `<source>` plus an
# `<img>` that has an `alt` attribute, then audits AAA in both themes with NO
# color-contrast exclude. External image URLs are fine — axe audits the DOM.
RSpec.describe "Picture component accessibility", type: :system do
  # `let`, NOT a top-level constant: a constant assigned inside an RSpec.describe
  # block leaks to ::SCOPE, so multiple scoped 0b specs would clobber each other and
  # axe would scope to the wrong selector ("No elements found for include").
  let(:scope) { [ "#pic-scope" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "default: renders art-directed sources plus a named base img and passes AAA in both themes" do
    visit "/rails/view_components/ui/picture_component/default"

    expect(page).to have_css("#pic-scope picture source", minimum: 1, visible: :all)
    expect(page).to have_css("#pic-scope picture img[alt]", visible: :all)
    expect_aaa_in_both_themes
  end

  it "formats: renders format-fallback sources plus a named base img and passes AAA in both themes" do
    visit "/rails/view_components/ui/picture_component/formats"

    expect(page).to have_css("#pic-scope picture source", minimum: 1, visible: :all)
    expect(page).to have_css("#pic-scope picture img[alt]", visible: :all)
    expect_aaa_in_both_themes
  end
end
