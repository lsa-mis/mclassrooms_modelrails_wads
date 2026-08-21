# frozen_string_literal: true

require "rails_helper"

# Submenus follow the WAI-ARIA APG menu pattern: the sub-trigger is itself a `menuitem`
# of the parent menu carrying `aria-haspopup="menu"` + `aria-expanded`, and it owns a
# nested `role="menu"`.
#
# The sub-trigger belongs to TWO controllers — an item of the outer `menu`, and the
# trigger of its own submenu. That works because the nested controller uses a distinct
# identifier (`submenu`), so `data-menu-target="item"` still resolves to the outer menu
# and keeps the sub-trigger in the parent's arrow-key rotation.
RSpec.describe "UI::DropdownMenuComponent submenus", type: :component do
  # The panel renders `hidden` (closed), so every query is visible: :all.
  def menu(&block)
    render_inline(UI::DropdownMenuComponent.new) do |c|
      c.with_trigger { "Actions" }
      block.call(c)
    end
  end

  before do
    menu do |c|
      c.with_item { "Edit" }
      c.with_item(submenu: "Share") do |sub|
        sub.with_item { "Email" }
        sub.with_item(href: "/x") { "Copy link" }
      end
    end
  end

  it "renders the sub-trigger as a menuitem of the parent menu" do
    trigger = page.find("[data-submenu-target=trigger]", visible: :all)

    expect(trigger["role"]).to eq("menuitem")
    expect(trigger["data-menu-target"]).to eq("item")
  end

  it "announces that the sub-trigger opens a menu, initially closed" do
    trigger = page.find("[data-submenu-target=trigger]", visible: :all)

    expect(trigger["aria-haspopup"]).to eq("menu")
    expect(trigger["aria-expanded"]).to eq("false")
    expect(trigger["aria-controls"]).to eq(page.find("[data-submenu-target=panel]", visible: :all)["id"])
  end

  it "nests a real menu whose items belong to the submenu, not the parent" do
    panel = page.find("[data-submenu-target=panel]", visible: :all)

    expect(panel["role"]).to eq("menu")
    expect(panel).to have_css("[role=menuitem][data-submenu-target=item]", count: 2, visible: :all)
    expect(panel).to have_no_css("[data-menu-target=item]", visible: :all)
  end

  it "keeps the parent's own items in its rotation alongside the sub-trigger" do
    expect(page).to have_css("[data-menu-target=item]", count: 2, visible: :all)
  end

  it "supports links inside a submenu" do
    expect(page).to have_css("a[role=menuitem][href='/x']", text: "Copy link", visible: :all)
  end
end
