# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + behavior proof for the context_menu component.
#
# The menu opens on right-click (contextmenu) at the pointer, AND on Shift+F10 / the
# ContextMenu key while the host has focus (WCAG 2.1.1 keyboard parity). We open it both
# ways and audit the LIVE menu.
#
# NOTE: the per-spec axe call runs axe's default (AA) rule set; the authoritative AAA 7:1
# audit is the CI-only wcag2aaa after-hook (spec/support/playwright_accessibility.rb).
RSpec.describe "Context menu component accessibility", type: :system do
  before { visit "/rails/view_components/ui/context_menu_component/basic" }

  def host
    find("[data-menu-target='trigger']")
  end

  def focused_text
    page.evaluate_script("document.activeElement.textContent.trim()")
  end

  def open_by_right_click
    host.right_click
    expect(page).to have_css("[role='menu']:not([hidden])")
  end

  it "right-click opens a menu that passes AAA in both themes" do
    expect(page).to have_css("[data-menu-target='trigger'][aria-haspopup='menu'][aria-expanded='false']")
    expect(page).to have_css("[role='menu'][aria-label]", visible: :all)

    open_by_right_click

    expect(page).to have_css("[data-menu-target='trigger'][aria-expanded='true']")
    scope = [ "[role='menu']:not([hidden])" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "opens via the keyboard (Shift+F10 on the focused host) and focuses the first item" do
    page.evaluate_script("document.querySelector('[data-menu-target=trigger]').focus()")
    cdp_browser.keyboard.type(%i[shift f10])

    expect(page).to have_css("[role='menu']:not([hidden])")
    expect(focused_text).to eq("Edit")
  end

  # The trigger carries role="button" — so it must HONOR button activation.
  # Enter and Space open the menu (anchored to the trigger) and focus the
  # first item, not just the Shift+F10 path (2026-07-13 review).
  %w[Enter Space].each do |key|
    it "opens on #{key} (honoring role=button) and focuses the first item" do
      page.evaluate_script("document.querySelector('[data-menu-target=trigger]').focus()")
      cdp_press(key)

      expect(page).to have_css("[role='menu']:not([hidden])")
      expect(focused_text).to eq("Edit")
    end
  end

  it "ArrowDown wraps and SKIPS the disabled item" do
    open_by_right_click # focus on "Edit"

    cdp_press(:down) # Duplicate
    expect(focused_text).to eq("Duplicate")
    cdp_press(:down) # skips disabled "Archive" → "Open docs"
    expect(focused_text).to eq("Open docs")
    cdp_press(:down) # wraps → "Edit"
    expect(focused_text).to eq("Edit")
  end

  it "type-ahead focuses the next item starting with the typed letter" do
    open_by_right_click
    cdp_browser.keyboard.type("d") # → "Duplicate"
    expect(focused_text).to eq("Duplicate")
  end

  it "closes on Escape and returns focus to the host" do
    open_by_right_click
    cdp_press(:escape)

    expect(page).to have_css("[role='menu'][hidden]", visible: :all)
    expect(page).to have_css("[data-menu-target='trigger'][aria-expanded='false']")
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-haspopup')")).to eq("menu")
  end

  it "closes on an outside click" do
    open_by_right_click
    cdp_click_at(5, 5)
    expect(page).to have_css("[role='menu'][hidden]", visible: :all)
  end
end
