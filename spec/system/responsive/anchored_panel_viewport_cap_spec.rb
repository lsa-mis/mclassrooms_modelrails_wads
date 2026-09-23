# frozen_string_literal: true

require "rails_helper"

# The compiled-CSS half of modelrails_ui #211. An anchored panel wider than the
# screen overflows it, and `position-try-fallbacks` cannot rescue that — flipping
# needs room on the other side, and a panel wider than the viewport has none. So
# every anchored panel the component sizes carries a ceiling resolved against the
# viewport (`max-w-[calc(100vw-2rem)]`).
#
# Why this test exists HERE rather than in the gem: the gem's browser lane serves
# no compiled stylesheet, so upstream can only prove the class ships. It cannot
# prove the class produces a real declaration. That matters more than it sounds —
# `calc(100vw-2rem)` is invalid CSS unspaced, so a wrong spelling would ship the
# class, pass the gem's gate, and bound nothing at all.
#
# Why it is not the bounding-box assertion the ledger already makes
# (spec/system/operations_activity_ledger_spec.rb, "keeps the range panel inside
# a 390px viewport"): that panel is a fixed 288px against a 390px viewport, so it
# fits with room to spare and its box test passes whether or not the ceiling
# exists. Measured, not assumed — stripping the cap leaves that test green. The
# ceiling is the thing that changed, so the ceiling is what this asserts.
RSpec.describe "Anchored panels — viewport ceiling", type: :system do
  # `basic` rather than a hand-built page: the preview renders the vendored
  # component itself, so this cannot drift from what the app actually ships.
  def open_popover
    visit "/rails/view_components/ui/popover_component/basic"
    find("[data-floating-target=trigger]").click
    expect(page).to have_css("[data-floating-target=panel]")
  end

  def panel_ceiling
    page.evaluate_script(<<~JS)
      (() => {
        const p = document.querySelector("[data-floating-target=panel]");
        return { maxWidth: getComputedStyle(p).maxWidth, viewport: window.innerWidth };
      })()
    JS
  end

  it "resolves the panel's max-width against the viewport at phone width" do
    with_viewport(ResponsiveViewport::PHONE) do
      open_popover
      measured = panel_ceiling

      # A resolved length, not the literal `calc(...)` and not `none`. `none` is
      # what an uncapped panel reports, and it is the regression this guards.
      expect(measured["maxWidth"]).to match(/\A[\d.]+px\z/),
        "expected a resolved px ceiling, got #{measured["maxWidth"].inspect} — " \
        "`none` means the cap never reached compiled CSS"

      expect(measured["maxWidth"].to_f).to be <= (measured["viewport"] - 32),
        "the ceiling must leave a gutter on both sides of a #{measured["viewport"]}px viewport"

      expect(axe_violations_in_both_themes).to be_empty,
        axe_violations_in_both_themes.join("\n")
    end
  end

  # The ceiling is viewport-relative, so it has to move with the viewport. A
  # fixed rem value would satisfy the assertion above at one width and fail here.
  it "tracks the viewport rather than resolving to a fixed width" do
    phone = with_viewport(ResponsiveViewport::PHONE) do
      open_popover
      panel_ceiling["maxWidth"].to_f
    end

    tablet = with_viewport(ResponsiveViewport::TABLET) do
      open_popover
      panel_ceiling["maxWidth"].to_f
    end

    expect(tablet).to be > phone,
      "ceiling did not grow with the viewport (#{phone}px at phone, #{tablet}px at tablet) — " \
      "it is resolving to a fixed length rather than against 100vw"
  end
end
