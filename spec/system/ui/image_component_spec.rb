# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility proof for the image component.
#
# The image wrapper forces an explicit alt decision at the call site: a meaningful
# image gets real alt text, a decorative one gets alt="" (which screen readers
# skip). This spec asserts that contract on each scenario and audits the meaningful
# scenarios scoped to the <img> subtree with NO color-contrast exclude. NOTE: the
# per-spec assertion below runs axe's default (AA) rule set; the authoritative
# AAA 7:1 audit is the wcag2aaa after-hook that fires under CI (see
# spec/support/playwright_accessibility.rb).
RSpec.describe "Image component accessibility", type: :system do
  it "default renders an img with non-empty alt and passes AAA in both themes" do
    visit "/rails/view_components/ui/image_component/default"

    expect(page).to have_css("img[alt='A black puppy sitting on a wooden floor']")

    audit_img
  end

  it "responsive renders srcset + sizes and passes AAA in both themes" do
    visit "/rails/view_components/ui/image_component/responsive"

    expect(page).to have_css("img[srcset][sizes]")

    audit_img
  end

  it "decorative renders alt='' and passes AAA in both themes" do
    visit "/rails/view_components/ui/image_component/decorative"

    expect(page).to have_css("img[alt='']")

    audit_img
  end

  def audit_img
    scope = [ "img" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
