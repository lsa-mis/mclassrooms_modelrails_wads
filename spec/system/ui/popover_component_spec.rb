# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + behavior proof for the popover component.
#
# JS-BEHAVIOR pattern: the panel lives in the DOM but stays hidden until the trigger
# fires. We OPEN it via the real button and audit the LIVE panel.
#
# NOTE: the per-spec axe call runs axe's default (AA) rule set; the authoritative AAA
# 7:1 audit is the CI-only wcag2aaa after-hook (spec/support/playwright_accessibility.rb).
RSpec.describe "Popover component accessibility", type: :system do
  def open_popover
    find("button[aria-haspopup='dialog']").click
    expect(page).to have_css("[role='dialog']:not([hidden])")
  end

  %w[basic positioned].each do |scenario|
    it "#{scenario}: opens a popover that passes AAA in both themes" do
      visit "/rails/view_components/ui/popover_component/#{scenario}"

      expect(page).to have_css("button[aria-haspopup='dialog'][aria-expanded='false']")
      expect(page).to have_css("[role='dialog'][aria-label]", visible: :all)

      open_popover

      expect(page).to have_css("button[aria-haspopup='dialog'][aria-expanded='true']")

      scope = [ "[role='dialog']:not([hidden])" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  it "opens from the keyboard (real button — Enter)" do
    visit "/rails/view_components/ui/popover_component/basic"
    find("button[aria-haspopup='dialog']").send_keys(:enter)

    expect(page).to have_css("[role='dialog']:not([hidden])")
  end

  it "closes on Escape and returns focus to the trigger" do
    visit "/rails/view_components/ui/popover_component/basic"
    open_popover

    # cdp_press, not page.send_keys: Cuprite's send_keys clicks the active element
    # (the focused panel) before typing, which can steal the focus this test asserts on.
    cdp_press("Escape")

    expect(page).to have_css("[role='dialog'][hidden]", visible: :all)
    expect(page).to have_css("button[aria-haspopup='dialog'][aria-expanded='false']")
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-haspopup')")).to eq("dialog")
  end

  it "closes on an outside click" do
    visit "/rails/view_components/ui/popover_component/basic"
    open_popover

    cdp_click_at(5, 5)

    expect(page).to have_css("[role='dialog'][hidden]", visible: :all)
  end
end
