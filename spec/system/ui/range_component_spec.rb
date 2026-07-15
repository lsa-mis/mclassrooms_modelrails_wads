# frozen_string_literal: true

require "rails_helper"

# 0b live-sync proof for the range component's `show_value: true` readout.
#
# The render harness verifies the WIRING (data-controller="range", the input's
# data-action / data-range-target, the <output> target) but has no JS runtime, so
# it cannot prove the `range` Stimulus controller actually mirrors the slider into
# the <output>. This spec exercises that in a real browser:
#   1. The controller's connect() resyncs the <output> to the input value on load.
#   2. Moving the slider (set value + dispatch an `input` event) updates the <output>.
# Dragging a native range thumb is unreliable, so we drive the input value + event
# via Playwright's evaluate instead.
RSpec.describe "Range component live value readout", type: :system do
  RANGE_PREVIEW = "/rails/view_components/ui/range_component"
  RANGE_DISPLAY_SCENARIO = "#{RANGE_PREVIEW}/with_value_display"

  RANGE_INPUT_SELECTOR = "input[type='range'][data-range-target='input']"
  RANGE_OUTPUT_SELECTOR = "output[data-range-target='output']"

  # Reads the live <output> text off the page.
  def output_text
    find(RANGE_OUTPUT_SELECTOR).text
  end

  # Sets the slider's value and dispatches an `input` event (what the user's drag
  # would fire), driving the `input->range#sync` action on the live page.
  def set_range_value(new_value)
    cdp_execute(<<~JS)
      (() => {
        const input = document.querySelector(#{RANGE_INPUT_SELECTOR.to_json});
        input.value = #{new_value.to_json};
        input.dispatchEvent(new Event("input", { bubbles: true }));
      })()
    JS
  end

  it "syncs the <output> to the slider value on connect" do
    visit RANGE_DISPLAY_SCENARIO

    expect(page).to have_css(RANGE_INPUT_SELECTOR)
    expect(page).to have_css("div[data-controller='range']")

    # connect() resyncs from the input value (60). If the controller never
    # registered, the SSR text would still be 60, so we further prove the live
    # path below by CHANGING the value.
    expect(output_text).to eq("60")
  end

  it "updates the <output> live when the slider value changes" do
    visit RANGE_DISPLAY_SCENARIO
    expect(page).to have_css(RANGE_INPUT_SELECTOR)
    expect(output_text).to eq("60")

    set_range_value(25)

    # If the live sync is dead, this stays "60" and the spec fails (do NOT fudge).
    expect(page).to have_css(RANGE_OUTPUT_SELECTOR, text: "25")
    expect(output_text).to eq("25")
  end

  it "passes AAA in both themes (output live region + text-text-body token)" do
    visit RANGE_DISPLAY_SCENARIO
    expect(page).to have_css(RANGE_OUTPUT_SELECTOR)

    # Scope to the component (its external label + the controller-wrapped
    # slider/output) so the minimal preview host's non-WCAG best-practice
    # advisories (landmark-one-main, page-has-heading-one) stay out of scope.
    # No color-contrast exclude (`exclude: []`) — the <output>'s text-text-body
    # readout and the slider's interactive tokens are held to AAA here.
    scope = [ "label", "div[data-controller='range']" ]
    expect(axe_clean_in_both_themes?(exclude: [], include: scope)).to(
      be(true),
      axe_violations_in_both_themes(exclude: [], include: scope).join("\n")
    )
  end
end
