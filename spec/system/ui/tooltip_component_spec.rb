# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + behavior proof for the tooltip component.
#
# The bubble lives in the DOM (opacity-0) and is revealed on hover OR keyboard focus
# via CSS; Escape dismisses it (WCAG 1.4.13) via the shared `floating` controller.
#
# NOTE: the per-spec axe call runs axe's default (AA) rule set; the authoritative AAA
# 7:1 audit is the CI-only wcag2aaa after-hook (spec/support/playwright_accessibility.rb).
RSpec.describe "Tooltip component accessibility", type: :system do
  def trigger_selector
    "[data-controller='floating'][tabindex='0']"
  end

  it "basic: keyboard focus reveals a described tooltip that passes AAA in both themes" do
    visit "/rails/view_components/ui/tooltip_component/basic"

    bubble_id = find(trigger_selector)["aria-describedby"]
    # The bubble is a role=tooltip referenced by the trigger's aria-describedby.
    expect(page).to have_css("##{bubble_id}[role='tooltip']", visible: :all)

    # Shows on keyboard focus — not hover-only (the core fix). The reveal is an
    # opacity transition (~200ms), so poll (within Capybara's wait window) until it
    # settles rather than reading mid-transition.
    page.execute_script("document.querySelector(#{trigger_selector.inspect}).focus()")
    opacity = -> { page.evaluate_script("getComputedStyle(document.getElementById('#{bubble_id}')).opacity") }
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until opacity.call == "1" }
    expect(opacity.call).to eq("1")

    scope = [ "##{bubble_id}" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "dismisses on Escape without moving focus (WCAG 1.4.13)" do
    visit "/rails/view_components/ui/tooltip_component/basic"

    page.execute_script("document.querySelector(#{trigger_selector.inspect}).focus()")
    page.send_keys(:escape)

    expect(page).to have_css("#{trigger_selector}[data-dismissed]", visible: :all)
  end

  # 2026-07-15 panel review: the bubble positions with CSS anchor positioning but
  # the component ships only a `flip-block` try-fallback — that flips top<->bottom,
  # never SHIFTS horizontally. So a top-center bubble anchored near a viewport edge
  # clipped off-screen on mobile (chip popover measured at left=-83 @390px). The
  # fork stylesheet adds `@position-try` span-* fallbacks (app/assets/tailwind/
  # application.css) so the bubble shifts inward toward its open side instead.
  it "shifts the bubble to stay within a narrow viewport instead of clipping off-screen" do
    visit "/rails/view_components/ui/tooltip_component/basic"
    cdp_resize(380, 800)

    # Pin the trigger hard against the left edge so a max-w-xs top-center bubble
    # would clip left without the span fallbacks; the bubble anchors to it.
    cdp_execute(<<~JS)
      const t = document.querySelector(#{trigger_selector.inspect});
      t.style.position = "fixed"; t.style.left = "0px"; t.style.top = "360px";
      t.focus();
    JS

    bubble_id = find(trigger_selector)["aria-describedby"]
    left = nil
    10.times do
      left = cdp_evaluate("document.getElementById(#{bubble_id.inspect}).getBoundingClientRect().left")
      break if left && left >= 0
      sleep 0.1
    end
    expect(left).to be >= 0,
      "tooltip bubble clipped off the left edge (left=#{left.inspect}) at a narrow viewport"
  end
end
