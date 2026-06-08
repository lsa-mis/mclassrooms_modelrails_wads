# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility proof for the breadcrumb component. Static nav (no JS); we assert
# the landmark + aria-current + axe-AAA in both themes. NOTE: per-spec axe runs AA locally; the
# AAA 7:1 audit is the CI-only wcag2aaa hook.
RSpec.describe "Breadcrumb component accessibility", type: :system do
  before { visit "/rails/view_components/ui/breadcrumb_component/basic" }

  it "renders a breadcrumb landmark that passes AAA in both themes" do
    expect(page).to have_css("nav[aria-label='Breadcrumb'] ol")
    expect(page).to have_css("[aria-current='page']", text: "Data")
    expect(page).to have_link("Home")
    expect(page).to have_link("Library")
    expect(page).not_to have_link("Data")

    scope = [ "nav[aria-label='Breadcrumb']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
