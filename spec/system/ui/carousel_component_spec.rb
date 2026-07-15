# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + BEHAVIOR proof for the carousel component.
#
# We assert OUTCOMES, not wiring: Next actually translates the track and moves
# aria-current; the 2.2.2 pause mechanism flips the live region to polite.
#
# NOTE: the per-spec axe call runs axe's default (AA) rule set; the authoritative
# AAA 7:1 audit is the CI-only wcag2aaa after-hook (spec/support/playwright_accessibility.rb).
RSpec.describe "Carousel component accessibility", type: :system do
  let(:scope) { [ "[data-test='carousel']" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "default: carousel group + slide labels; AAA in both themes" do
    visit "/rails/view_components/ui/carousel_component/default"

    expect(page).to have_css("[role='group'][aria-roledescription='carousel'][aria-label='Featured photos']")
    expect(page).to have_css("[aria-roledescription='slide']", count: 3)
    expect_aaa_in_both_themes
  end

  it "Next actually translates the track and moves aria-current (outcome, not wiring)" do
    visit "/rails/view_components/ui/carousel_component/default"

    expect(page).to have_css("[data-carousel-target='dots'] button[aria-current='true']:first-child")

    find("button[aria-label='Next slide']").click

    transform = page.evaluate_script(
      "getComputedStyle(document.querySelector('[data-carousel-target=track]')).transform"
    )
    expect(transform).not_to eq("none") # the track moved

    expect(page).to have_css("[data-carousel-target='dots'] button:nth-child(2)[aria-current='true']")

    # ...and slide 2 lands FLUSH at the container's left edge — not partially
    # scrolled. Regression guard for the slide-width fix: `min-w-full` let a wide
    # image overflow the slide to its intrinsic 600px while the track translated by
    # one 448px container-width, leaving slide 2 offset ~152px into the viewport.
    # Wait for the transition to settle, then measure the offset.
    #
    # Container selector: `[data-controller='carousel']`, NOT the `.overflow-hidden`
    # utility class. That class is shared with each per-slide wrapper (SLIDE_CLS
    # applies `overflow-hidden` too, for an unrelated flex-shrink reason — see
    # carousel_component.rb), so `.overflow-hidden` is ambiguous: it happened to
    # resolve to the true outer container only because that node is first in
    # document order, an implicit and fragile coupling. `data-controller` is
    # unique and semantic.
    offset = page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      const track = document.querySelector("[data-carousel-target='track']")
      const measure = () => {
        const container = document.querySelector("[data-test='carousel'] [data-controller='carousel']")
        const slide2 = track.querySelectorAll("[aria-roledescription='slide']")[1]
        done(Math.round(slide2.getBoundingClientRect().left - container.getBoundingClientRect().left))
      }
      let settled = false
      const finish = () => { if (!settled) { settled = true; measure() } }
      track.addEventListener("transitionend", finish, { once: true })
      setTimeout(finish, 600)
    JS
    expect(offset.abs).to be <= 2
  end

  it "autoplay: pause flips the live region to polite (WCAG 2.2.2 mechanism)" do
    visit "/rails/view_components/ui/carousel_component/autoplay"

    find("button[data-carousel-target='pause']").click

    expect(page).to have_css(
      "[data-carousel-target='status'][aria-live='polite']", visible: :all
    )
  end

  it "autoplay: passes AAA in both themes" do
    visit "/rails/view_components/ui/carousel_component/autoplay"

    expect(page).to have_css("[role='group'][aria-roledescription='carousel'][aria-label='Auto gallery']")
    expect_aaa_in_both_themes
  end
end
