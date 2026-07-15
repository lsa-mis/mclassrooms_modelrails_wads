# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + behavior proof for the hover_card component.
#
# JS hover-intent: the card opens on hover/focus and closes on leave/blur after a
# short delay (so the pointer can cross to the card and click it). Opening sets
# `data-state="open"` on the wrapper; Escape closes and returns focus to the trigger.
#
# NOTE: the per-spec axe call runs axe's default (AA) rule set; the authoritative AAA
# 7:1 audit is the CI-only wcag2aaa after-hook (spec/support/playwright_accessibility.rb).
#
# Focus mechanism: the component listens for a real `focusin` event to open. A
# JS-level `element.focus()` (via evaluate/execute_script) moves `document.
# activeElement` but does NOT dispatch `focusin` under CDP — verified empirically
# (a probe confirmed `activeElement` updates while a `focusin` listener never
# fires, even combined into one evaluate call, ruling out a call-ordering
# artifact). So we reach the trigger link via REAL CDP-dispatched Tab presses
# (native browser tab-navigation), matching the pattern already established and
# verified in switch_component_spec.rb for an analogous focus-trust gap.
RSpec.describe "Hover card component accessibility", type: :system do
  def tab_to_trigger
    cdp_execute("document.activeElement && document.activeElement.blur()")
    trigger_selector = '[data-controller="floating"] a'
    reached = (1..10).any? do
      cdp_press("Tab")
      cdp_evaluate("document.activeElement === document.querySelector(#{trigger_selector.to_json})")
    end
    raise "could not reach the hover-card trigger via Tab navigation" unless reached
  end

  it "basic: keyboard focus opens a reachable card that passes AAA in both themes" do
    visit "/rails/view_components/ui/hover_card_component/basic"

    # Opens on keyboard focus of the trigger link.
    tab_to_trigger
    expect(page).to have_css("[data-controller='floating'][data-state='open']")

    # The card's interactive content is present and reachable while open.
    expect(page).to have_css("[data-floating-target='panel']")
    expect(page).to have_link("View profile")

    scope = [ "[data-floating-target='panel']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "closes on Escape and returns focus to the trigger" do
    visit "/rails/view_components/ui/hover_card_component/basic"

    tab_to_trigger
    expect(page).to have_css("[data-controller='floating'][data-state='open']")

    cdp_press("Escape")

    expect(page).to have_css("[data-controller='floating'][data-state='closed']")
    expect(page.evaluate_script("document.activeElement.tagName")).to eq("A")
  end
end
