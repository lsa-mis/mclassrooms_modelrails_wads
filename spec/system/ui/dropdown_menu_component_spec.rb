# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + behavior proof for the dropdown_menu component.
#
# JS-BEHAVIOR pattern: the menu lives in the DOM but stays hidden until the trigger
# fires. We OPEN it via the real button and audit the LIVE menu.
#
# NOTE: the per-spec axe call runs axe's default (AA) rule set; the authoritative AAA
# 7:1 audit is the CI-only wcag2aaa after-hook (spec/support/playwright_accessibility.rb).
RSpec.describe "Dropdown menu component accessibility", type: :system do
  def open_menu
    find("button[aria-haspopup='menu']").click
    expect(page).to have_css("[role='menu']:not([hidden])")
  end

  def focused_text
    page.evaluate_script("document.activeElement.textContent.trim()")
  end

  %w[basic positioned].each do |scenario|
    it "#{scenario}: opens a menu that passes AAA in both themes" do
      visit "/rails/view_components/ui/dropdown_menu_component/#{scenario}"

      expect(page).to have_css("button[aria-haspopup='menu'][aria-expanded='false']")
      expect(page).to have_css("[role='menu'][aria-labelledby]", visible: :all)

      open_menu

      expect(page).to have_css("button[aria-haspopup='menu'][aria-expanded='true']")

      scope = [ "[role='menu']:not([hidden])" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  it "opens from the keyboard (Enter on the trigger) and focuses the first item" do
    visit "/rails/view_components/ui/dropdown_menu_component/basic"
    find("button[aria-haspopup='menu']").native.node.focus
    cdp_press(:enter)

    expect(page).to have_css("[role='menu']:not([hidden])")
    expect(focused_text).to eq("Edit")
  end

  it "ArrowUp on the trigger opens and focuses the last item" do
    visit "/rails/view_components/ui/dropdown_menu_component/basic"
    find("button[aria-haspopup='menu']").native.node.focus
    cdp_press(:up)

    expect(focused_text).to eq("Open docs")
  end

  it "ArrowDown wraps and SKIPS the disabled item" do
    visit "/rails/view_components/ui/dropdown_menu_component/basic"
    open_menu # focus on "Edit"

    cdp_press(:down) # Duplicate
    expect(focused_text).to eq("Duplicate")
    cdp_press(:down) # skips disabled "Archive" → "Open docs"
    expect(focused_text).to eq("Open docs")
    cdp_press(:down) # wraps → "Edit"
    expect(focused_text).to eq("Edit")
  end

  it "type-ahead focuses the next item starting with the typed letter" do
    visit "/rails/view_components/ui/dropdown_menu_component/basic"
    open_menu # focus on "Edit"

    cdp_browser.keyboard.type("d") # → "Duplicate"
    expect(focused_text).to eq("Duplicate")
  end

  it "End focuses the last item, Home the first" do
    visit "/rails/view_components/ui/dropdown_menu_component/basic"
    open_menu

    cdp_press(:end)
    expect(focused_text).to eq("Open docs")
    cdp_press(:home)
    expect(focused_text).to eq("Edit")
  end

  it "closes on Escape and returns focus to the trigger" do
    visit "/rails/view_components/ui/dropdown_menu_component/basic"
    open_menu

    cdp_press(:escape)

    expect(page).to have_css("[role='menu'][hidden]", visible: :all)
    expect(page).to have_css("button[aria-haspopup='menu'][aria-expanded='false']")
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-haspopup')")).to eq("menu")
  end

  it "closes on an outside click" do
    visit "/rails/view_components/ui/dropdown_menu_component/basic"
    open_menu

    cdp_click_at(5, 5)

    expect(page).to have_css("[role='menu'][hidden]", visible: :all)
  end
end
