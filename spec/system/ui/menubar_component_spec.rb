# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + behavior proof for the menubar component.
#
# Two-level APG menubar: a horizontal bar (←/→ roving) + per-item submenus (the reused `menu`
# controller). The menubar coordinator drives submenus via Stimulus outlets; key-routing is
# implicit (defaultPrevented skip; ←/→ bubble). NOTE: per-spec axe runs AA locally; the AAA
# 7:1 audit is the CI-only wcag2aaa hook.
RSpec.describe "Menubar component accessibility", type: :system do
  before { visit "/rails/view_components/ui/menubar_component/basic" }

  def bar_item(text)
    find("button[role='menuitem']", text: text)
  end

  def focused_text
    page.evaluate_script("document.activeElement.textContent.trim()")
  end

  it "renders a menubar and opens a submenu that passes AAA in both themes" do
    expect(page).to have_css("[role='menubar'][aria-label='Main']")
    expect(page).to have_css("button[role='menuitem'][aria-haspopup='menu']", minimum: 3)

    bar_item("File").click
    expect(page).to have_css("[role='menu']:not([hidden])")
    expect(bar_item("File")["aria-expanded"]).to eq("true")

    scope = [ "[role='menu']:not([hidden])" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "ArrowDown on a bar item opens its submenu and focuses the first item" do
    bar_item("File").native.node.focus
    cdp_press(:down)
    expect(page).to have_css("[role='menu']:not([hidden])")
    expect(focused_text).to eq("New file")
  end

  it "ArrowRight/Left move between bar items (no submenu open)" do
    bar_item("File").native.node.focus
    cdp_press(:right)
    expect(focused_text).to eq("Edit")
    cdp_press(:right)
    expect(focused_text).to eq("View")
    cdp_press(:right) # wraps
    expect(focused_text).to eq("File")
    cdp_press(:left) # wraps back
    expect(focused_text).to eq("View")
  end

  it "ArrowRight from inside an open submenu follows to the adjacent menu" do
    bar_item("File").native.node.focus
    cdp_press(:down) # File submenu open, focus "New file"
    expect(focused_text).to eq("New file")

    cdp_press(:right) # close File, open Edit, focus its first item
    expect(focused_text).to eq("Undo")
    expect(page).to have_css("[role='menu']:not([hidden])", count: 1)
    expect(bar_item("File")["aria-expanded"]).to eq("false")
    expect(bar_item("Edit")["aria-expanded"]).to eq("true")
  end

  it "ArrowDown wraps and SKIPS the disabled submenu item" do
    bar_item("File").native.node.focus
    cdp_press(:down) # New file
    cdp_press(:down) # Open…
    expect(focused_text).to eq("Open…")
    cdp_press(:down) # skips disabled "Open recent" → Settings
    expect(focused_text).to eq("Settings")
  end

  it "Escape closes the submenu and returns focus to the bar item" do
    bar_item("File").native.node.focus
    cdp_press(:down)
    cdp_press(:escape)
    expect(page).to have_css("[role='menu'][hidden]", visible: :all)
    expect(focused_text).to eq("File")
    expect(bar_item("File")["aria-expanded"]).to eq("false")
  end

  it "type-ahead at the bar level jumps to a matching item" do
    bar_item("File").native.node.focus
    cdp_browser.keyboard.type("e") # → Edit
    expect(focused_text).to eq("Edit")
  end

  it "clicking another bar item closes the open submenu (mouse mutual exclusion)" do
    bar_item("File").click
    expect(bar_item("File")["aria-expanded"]).to eq("true")

    bar_item("Edit").click # File's closeOnClickOutside fires as Edit's toggle opens Edit
    expect(bar_item("Edit")["aria-expanded"]).to eq("true")
    expect(bar_item("File")["aria-expanded"]).to eq("false")
    expect(page).to have_css("[role='menu']:not([hidden])", count: 1)
  end

  it "clicking outside closes the open submenu" do
    bar_item("File").click
    expect(page).to have_css("[role='menu']:not([hidden])")

    cdp_click_at(5, 5)
    expect(page).to have_css("[role='menu'][hidden]", visible: :all)
  end
end
