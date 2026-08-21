# frozen_string_literal: true

require "rails_helper"

# APG menu pattern: activating a `menuitemcheckbox`/`menuitemradio` changes its state and
# leaves the menu open, so a multi-select view menu is usable in one pass. Plain items
# still close on activation.
RSpec.describe "Checkable menu items", type: :system do
  let(:menu) { "[data-menu-target=menu]" }

  before do
    visit "/rails/view_components/ui/dropdown_menu_component/checkable_items"
    find("[data-menu-target=trigger]").click
    expect(page).to have_css(menu)
  end

  it "toggles a checkbox item without closing the menu" do
    item = find("[role=menuitemcheckbox]", text: "Show rulers")
    expect(item["aria-checked"]).to eq("false")

    item.click

    expect(find("[role=menuitemcheckbox]", text: "Show rulers")["aria-checked"]).to eq("true")
    expect(page).to have_css(menu)
  end

  it "moves the selection within a radio group and keeps the menu open" do
    find("[role=menuitemradio]", text: "Compact").click

    states = page.all("[role=menuitemradio]").map { |i| i["aria-checked"] }
    expect(states).to eq(%w[false true])
    expect(page).to have_css(menu)
  end

  it "still closes on a plain item" do
    find("[role=menuitem]", text: "Delete view").click

    expect(page).to have_no_css(menu)
  end
end
