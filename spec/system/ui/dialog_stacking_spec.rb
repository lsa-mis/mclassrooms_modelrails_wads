# frozen_string_literal: true

require "rails_helper"

# `modal_controller` warned "Stacked modals are not supported" and then called showModal()
# anyway. The browser has always supported it: a second showModal() puts that dialog above
# the first in the top layer, moves the focus trap, and gives it Escape. Verified directly
# — two dialogs open, no exception, the second topmost and focused.
#
# So the warning was telling the truth about nothing, on a path that works.
RSpec.describe "Stacked dialogs", type: :system do
  def press(key) = page.driver.browser.keyboard.type(key)

  # `close()` animates out before the dialog actually closes, so this has to be a WAITING
  # matcher. A bare `page.all(...).length` reads the pre-animation state and reports a
  # failure that is really just impatience.
  def expect_open_dialogs(count)
    expect(page).to have_css("dialog[open]", count: count, visible: :all)
  end

  before do
    visit "/rails/view_components/ui/dialog_component/stacked"
    click_button "Open form"
    expect(page).to have_css("dialog[open]")
    click_button "Discard"
  end

  it "opens the second dialog above the first" do
    expect_open_dialogs(2)
  end

  it "traps focus in the topmost dialog" do
    inner = page.evaluate_script(<<~JS)
      (() => {
        const dialogs = [...document.querySelectorAll("dialog[open]")];
        const top = dialogs[dialogs.length - 1];
        return top.contains(document.activeElement);
      })()
    JS

    expect(inner).to be(true)
  end

  it "closes only the topmost on Escape, leaving the one beneath open" do
    press(:Escape)

    expect_open_dialogs(1)
  end

  it "closes the remaining dialog on a second Escape" do
    press(:Escape)
    expect_open_dialogs(1)

    press(:Escape)

    expect_open_dialogs(0)
  end
end
