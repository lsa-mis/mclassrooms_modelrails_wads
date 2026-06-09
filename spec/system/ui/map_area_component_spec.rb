# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the map_area component.
#
# map_area renders an <img usemap> + <map> of <area> hotspots — a roleless,
# non-interactive container with no live-region role to scope by. The default
# preview wraps the map in `#ma-scope` so axe audits the COMPONENT subtree, not
# the host chrome (the minimal preview layout emits best-practice advisories like
# landmark-one-main that are not WCAG and not about the map).
#
# The component's key a11y fix: every interactive <area href> is forced to carry a
# non-blank `alt` (its accessible name) — this spec asserts that contract on the
# rendered markup, then audits the subtree with NO color-contrast exclude.
RSpec.describe "Map / Area component accessibility", type: :system do
  # `let`, NOT a top-level constant: a constant assigned inside an RSpec.describe
  # block leaks to ::SCOPE, so multiple scoped 0b specs would clobber each other and
  # axe would scope to the wrong selector ("No elements found for include").
  let(:scope) { [ "#ma-scope" ] }

  it "default: renders the usemap image + labeled areas and passes AAA in both themes" do
    visit "/rails/view_components/ui/map_area_component/default"

    # The base image is wired to the map and carries real alt text.
    expect(page).to have_css("#ma-scope img[usemap][alt]")

    # Every interactive area carries an href AND a non-blank alt (the key a11y fix).
    areas = page.all("#ma-scope map area[href][alt]", visible: :all)
    expect(areas).not_to be_empty
    areas.each do |area|
      expect(area[:alt].to_s.strip).not_to be_empty
    end

    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
