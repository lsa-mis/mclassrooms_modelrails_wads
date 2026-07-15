# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Complete dialog behavior", type: :system do
  it "opens via its trigger, traps focus, and closes on Escape — accessibly" do
    visit "/rails/view_components/ui/dialog_component/basic"

    click_button "Open dialog"
    expect(page).to have_css("dialog[open]")

    # focus moved into the dialog (behavior axe can't see)
    focused_in_dialog = page.evaluate_script(
      "document.querySelector('dialog[open]').contains(document.activeElement)"
    )
    expect(focused_in_dialog).to be(true)

    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    # Escape closes (reopen first if theme switching closed it)
    click_button "Open dialog" unless page.has_css?("dialog[open]")
    cdp_press("Escape")
    expect(page).to have_no_css("dialog[open]")
  end
end
