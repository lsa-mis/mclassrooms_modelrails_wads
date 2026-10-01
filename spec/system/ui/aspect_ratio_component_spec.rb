# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the aspect_ratio component.
#
# aspect_ratio is a roleless, presentational layout wrapper — it carries no role,
# no tabindex, and no focus ring, so there is no live-region selector to scope by
# (the alert pattern). Following the form_field pattern, each preview wraps the
# component in `#ar-scope` so axe audits the COMPONENT subtree, not the host chrome
# (the preview-host minimal layout yields the component next to a dev theme toggle
# and emits best-practice advisories — landmark-one-main, page-has-heading-one —
# that are NOT WCAG and NOT about the component).
#
# No color-contrast exclude: the wrapper frames slotted media that carries its own
# a11y (an `<img>` with `alt`), and a real contrast failure inside the scope would
# still fail this spec.
RSpec.describe "AspectRatio component accessibility", type: :system do
  # `let`, not a top-level constant (a constant inside describe leaks to ::SCOPE and
  # collides across scoped 0b specs → axe scopes to the wrong selector).
  let(:scope) { [ "#ar-scope" ] }

  it "default: renders a 16:9 ratio wrapper framing the slotted image; AAA in both themes" do
    visit "/rails/view_components/ui/aspect_ratio_component/default"

    expect(page).to have_css("#ar-scope div[style*='aspect-ratio']")
    expect(page).to have_css("#ar-scope img[alt='A river winding between forested cliffs']")
    expect_aaa_in_both_themes(include: scope)
  end

  it "square: renders a 1:1 ratio wrapper framing the slotted image; AAA in both themes" do
    visit "/rails/view_components/ui/aspect_ratio_component/square"

    expect(page).to have_css("#ar-scope div[style*='aspect-ratio']")
    expect(page).to have_css("#ar-scope img[alt='A black puppy sitting on a wooden floor']")
    expect_aaa_in_both_themes(include: scope)
  end
end
