# frozen_string_literal: true

require "rails_helper"

# ENHANCED preview-host proof for the timepicker (#463).
#
# The picker is a dialog popover of real role="spinbutton" fields whose
# keyboard contract IS ArrowUp/ArrowDown (the visible stepper buttons are
# decorative: aria-hidden, tabindex=-1). The old spec audited only the CLOSED
# default state, so a screen-reader user's entire data-entry path was
# unproven. These examples drive real CDP arrows through the open dialog.
RSpec.describe "Timepicker component accessibility and keyboard operation", type: :system do
  preview = "/rails/view_components/ui/timepicker_component/default"

  # `let` (used in helper defs); bare constants collide across workers (#608).
  let(:trigger_selector) { "button[data-timepicker-target='trigger']" }

  def open_picker
    find(trigger_selector).click
    expect(page).to have_css("[role='dialog'] [role='spinbutton']")
  end

  def spinbutton(index)
    page.evaluate_script(<<~JS)
      (() => {
        const sb = document.querySelectorAll("[role='spinbutton']")[#{index}];
        return sb && {
          now: sb.getAttribute("aria-valuenow"),
          text: sb.getAttribute("aria-valuetext")
        };
      })()
    JS
  end

  it "default (closed) passes AAA in both themes" do
    visit preview
    expect(page).to have_css(trigger_selector)

    scope = [ "[data-controller~='timepicker']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "open picker passes AAA in both themes (dialog + spinbuttons live)" do
    visit preview
    open_picker

    scope = [ "[data-controller~='timepicker']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "ArrowUp/ArrowDown step the hour spinbutton and keep ARIA values in sync" do
    visit preview
    open_picker

    page.execute_script("document.querySelectorAll(\"[role='spinbutton']\")[0].focus()")
    before = spinbutton(0)

    cdp_press("ArrowUp")
    after_up = spinbutton(0)
    expect(after_up["now"]).not_to eq(before["now"]),
      "ArrowUp must step the hour (aria-valuenow #{before["now"].inspect} unchanged)"

    cdp_press("ArrowDown")
    expect(spinbutton(0)["now"]).to eq(before["now"]),
      "ArrowDown must step back to the starting hour"
  end

  it "the decorative stepper buttons stay out of the tab order" do
    visit preview
    open_picker

    exposed = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("[role='dialog'] button"))
           .filter(btn => btn.getAttribute("aria-hidden") === "true" && btn.tabIndex !== -1)
           .length
    JS
    expect(exposed).to eq(0),
      "aria-hidden stepper buttons must carry tabindex=-1 or keyboard users tab onto invisible-to-AT controls"
  end
end
