# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the device_mockup component.
#
# DeviceMockup is a roleless decorative frame (a plain non-interactive `<div>`),
# so there is no live-region role to scope by. Each preview wraps the mockup in
# `#dm-scope` so axe audits the COMPONENT subtree, not the host chrome (the
# minimal preview layout emits best-practice advisories like landmark-one-main
# that are not WCAG and not about the mockup).
#
# The frame chrome (notch, traffic-light dots, fake address bar) is purely
# decorative and `aria-hidden`; only the slotted content (a real `<img>` with its
# own `alt`) is exposed to AT. This spec asserts the frame renders, the slotted
# image is present, and the decorative chrome is hidden — then audits each
# scenario scoped to `#dm-scope` with NO color-contrast exclude.
RSpec.describe "DeviceMockup component accessibility", type: :system do
  # `let`, NOT a top-level constant: a constant assigned inside an RSpec.describe
  # block leaks to ::SCOPE, so multiple scoped 0b specs would clobber each other and
  # axe would scope to the wrong selector ("No elements found for include").
  let(:scope) { [ "#dm-scope" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "phone: renders the frame, slotted image, and aria-hidden notch; passes AAA in both themes" do
    visit "/rails/view_components/ui/device_mockup_component/phone"

    expect(page).to have_css("#dm-scope img[alt='Mobile app home screen']")
    expect(page).to have_css("#dm-scope [aria-hidden='true']")
    expect_aaa_in_both_themes
  end

  it "browser: renders the frame, slotted image, and aria-hidden browser bar; passes AAA in both themes" do
    visit "/rails/view_components/ui/device_mockup_component/browser"

    expect(page).to have_css("#dm-scope img[alt='Analytics dashboard with charts']")
    expect(page).to have_css("#dm-scope [aria-hidden='true']")
    expect_aaa_in_both_themes
  end
end
