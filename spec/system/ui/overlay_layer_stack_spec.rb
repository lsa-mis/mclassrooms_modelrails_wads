# frozen_string_literal: true

require "rails_helper"

# Dismissable layers form a stack: Escape closes only the topmost one, so a menu opened
# inside a dialog closes the menu and leaves the dialog standing.
#
# Two independent mechanisms deliver that, and either one alone is sufficient — probed,
# not assumed. (a) `menu#navigate` calls `preventDefault()` on Escape, suppressing the
# browser's close request for the enclosing <dialog>. (b) The menu is promoted to the top
# layer as a `popover=manual`, so the close request resolves against the topmost top-layer
# element and never reaches the dialog. Dropping `close()` fails two examples; dropping
# `preventDefault()` alone fails none; dropping both it and the promotion fails all three.
#
# Keys go through Ferrum's keyboard rather than Capybara's `send_keys`. Capybara resolves
# an element and CLICKS it to take focus, which activates a menu item and closes the menu
# before the key is ever sent — a spec written that way passes no matter what the Escape
# handler does.
RSpec.describe "Overlay layer stack", type: :system do
  let(:menu) { "[data-menu-target=menu]" }
  let(:dialog) { "dialog[open]" }

  def press_escape
    page.driver.browser.keyboard.type(:Escape)
  end

  before do
    visit "/rails/view_components/ui/dialog_component/nested_menu"
    click_button "Open dialog"
    expect(page).to have_css(dialog)
    find("[data-menu-target=trigger]").click
    expect(page).to have_css(menu)
  end

  it "closes the topmost layer on Escape" do
    press_escape

    expect(page).to have_no_css(menu)
  end

  it "leaves the layer beneath it open" do
    press_escape

    expect(page).to have_css(dialog)
  end

  it "closes the next layer down on a second Escape" do
    press_escape
    expect(page).to have_no_css(menu)

    press_escape

    expect(page).to have_no_css(dialog)
  end
end
