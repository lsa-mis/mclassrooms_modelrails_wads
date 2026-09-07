# frozen_string_literal: true

require "rails_helper"

# The drawer already rendered a drag handle — a visual grabber that did nothing. An
# affordance that promises draggability and ignores the pointer is worse than none.
#
# Drag is an ADDITION, never the only way out: Escape and the close button are unchanged,
# because dragging is pointer-only and a keyboard or switch user cannot do it at all.
RSpec.describe "Drawer drag-to-dismiss", type: :system do
  def open_drawer
    visit "/rails/view_components/ui/drawer_component/basic"
    # The trigger slot renders inside a span carrying the open action, not a button.
    find("[data-action='click->modal#open']").click
    expect(page).to have_css("dialog[open]")
    settle
  end

  # The drawer animates up from translateY(100%), and `dialog[open]` is true the moment it
  # opens — long before the panel stops moving. Measuring the handle mid-animation gives a
  # position the pointer never lands on, and the press hits whatever has slid into that
  # spot instead. Wait for the panel to come to rest. The budget is the suite's, not a
  # stopwatch (#945).
  def settle
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop do
        first = handle_box["y"]
        sleep 0.05
        break if (handle_box["y"] - first).abs < 0.5
      end
    end
  end

  # The HANDLE, not the panel: the drag only starts from the grabber, and the drawer sits
  # at the bottom of the viewport so the panel's top edge is nowhere near it.
  def handle_box
    JSON.parse(page.evaluate_script(
      %{JSON.stringify(document.querySelector(".touch-none").getBoundingClientRect().toJSON())}
    ))
  end

  # A real pointer drag: press on the handle, move, release. Ferrum's mouse drives CDP,
  # so the controller sees genuine pointer events rather than synthesised ones.
  def drag(by:, steps: 6)
    box = handle_box
    x = box["x"] + box["width"] / 2
    y = box["y"] + box["height"] / 2
    mouse = page.driver.browser.mouse
    mouse.move(x: x, y: y).down
    mouse.move(x: x, y: y + by, steps: steps) if by.positive?
    mouse.up
  end

  before { open_drawer }

  # Deliberately modest: a bottom-anchored drawer only has its own height of travel below
  # the handle, so the assertion has to stay inside what a user can physically reach.
  it "dismisses when dragged far enough" do
    drag(by: 80)

    expect(page).to have_no_css("dialog[open]")
  end

  it "springs back when the drag is too small to be intentional" do
    drag(by: 8)

    expect(page).to have_css("dialog[open]")
  end

  # The control: without it, "dismisses when dragged far" could be passing because any
  # pointer interaction closes the drawer.
  it "stays open when pressed and released without moving" do
    drag(by: 0, steps: 1)

    expect(page).to have_css("dialog[open]")
  end

  it "still closes on Escape, which is the path a keyboard user has" do
    page.driver.browser.keyboard.type(:Escape)

    expect(page).to have_no_css("dialog[open]")
  end

  it "leaves no transform behind after springing back" do
    drag(by: 8)
    expect(page).to have_css("dialog[open]")

    transform = page.evaluate_script(
      %{document.querySelector("[data-modal-target=panel]").style.transform}
    )

    expect(transform).to satisfy { |t| t.nil? || t.empty? || t.include?("0px") }
  end
end
