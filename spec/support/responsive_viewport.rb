# frozen_string_literal: true

# Viewport-scoped helper for the responsive regression lane
# (spec/system/responsive/).
#
# Lane conventions (Wave 1, panel checkpoint 1):
# - `visit` INSIDE the `with_viewport` block, so the page lays out at the
#   target width instead of being resized post-render.
# - Assert geometry first (scrollWidth/clientWidth, bounding rects); assert
#   computed style only where no behavioral distinction exists — user-
#   scrollable vs clipped is one (programmatic scrolling works on both).
# - Prefer data-* hooks over Tailwind-utility class selectors: styling
#   classes carry no semantics and forks restyle them first.
# - Tag lane examples `skip_axe_hook: true` and assert
#   `axe_violations_in_both_themes` INSIDE the block: the suite-wide axe
#   hook runs after this helper's `ensure` restore, i.e. at the 1400x1400
#   desktop viewport, and can never see the narrow-viewport DOM this lane
#   protects.
# - Failure screenshots are captured after the restore too — they show the
#   DESKTOP layout of a narrow-viewport failure. Known limitation.
#
# `cdp_resize` (spec/support/cdp_helpers.rb) is the suite's one resize
# primitive; this wrapper adds scoping — the `ensure` restores the suite
# default so a leaked narrow viewport can never reframe later specs in the
# same parallel worker.
module ResponsiveViewport
  PHONE  = 375 # iPhone SE width — the tightest realistic phone we target
  TABLET = 768 # smallest width where Tailwind's md: variants still apply
  PHONE_HEIGHT = 667

  def with_viewport(width, height = PHONE_HEIGHT)
    cdp_resize(width, height)
    yield
  ensure
    cdp_resize(*CUPRITE_SCREEN_SIZE)
  end
end

RSpec.configure do |config|
  config.include ResponsiveViewport, type: :system
end
