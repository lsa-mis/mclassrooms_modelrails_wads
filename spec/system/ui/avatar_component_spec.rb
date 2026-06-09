# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the avatar component.
#
# Avatar is roleless: a photo renders as a decorative `<img>` and initials as a
# hue-tinted `<span>`, both `aria-hidden` by default. There is no live-region role
# to scope by, so each preview wraps the avatar in `#av-scope` and axe audits the
# COMPONENT subtree, not the host chrome (the minimal preview layout emits
# best-practice advisories like landmark-one-main that are not WCAG, not the avatar).
#
# No color-contrast exclude — a real contrast failure on the initials
# (`text-text-on-interactive` on `bg-interactive`, or `text-white` on
# `bg-hue-initials`) would still fail this spec, proving AAA in BOTH themes.
RSpec.describe "Avatar component accessibility", type: :system do
  # `let`, NOT a top-level constant: a constant assigned inside an RSpec.describe
  # block leaks to ::SCOPE, so multiple scoped 0b specs would clobber each other and
  # axe would scope to the wrong selector ("No elements found for include").
  let(:scope) { [ "#av-scope" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "image: renders the photo avatar and passes AAA in both themes" do
    visit "/rails/view_components/ui/avatar_component/image"

    expect(page).to have_css("#av-scope img[alt]")
    expect_aaa_in_both_themes
  end

  it "initials: renders the initials avatar and passes AAA in both themes" do
    visit "/rails/view_components/ui/avatar_component/initials"

    expect(page).to have_css("#av-scope span", text: "JD")
    expect_aaa_in_both_themes
  end
end
