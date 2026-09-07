# frozen_string_literal: true

require "rails_helper"

# ENHANCED preview-host proof for the date picker (#463).
#
# The picker is a dialog popover over a month grid with a roving tabindex
# (APG date-grid): exactly one day button is tabbable, arrows move focus,
# PageUp/PageDown change month, Escape closes back to the trigger. The old
# spec audited only the CLOSED default state, so the entire keyboard data-entry
# path was unproven. These examples drive real CDP key presses through the
# open grid.
RSpec.describe "Date picker component accessibility and keyboard operation", type: :system do
  preview = "/rails/view_components/ui/date_picker_component/default"

  # `let` (used in helper defs); bare constants collide across workers (#608).
  let(:trigger_selector) { "button[data-date-picker-target='trigger']" }

  def open_picker
    find(trigger_selector).click
    expect(page).to have_css("[data-date-picker-target='popover'][data-open='true']")
  end

  def focused_day_label
    page.evaluate_script("document.activeElement?.getAttribute('aria-label')")
  end

  def grid_month
    page.evaluate_script("document.querySelector('[role=grid]')?.getAttribute('aria-label')")
  end

  it "default (closed) passes AAA in both themes" do
    visit preview
    expect(page).to have_css(trigger_selector)

    scope = [ "[data-controller~='date-picker']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "open picker passes AAA in both themes (dialog + grid live)" do
    visit preview
    open_picker

    scope = [ "[data-controller~='date-picker']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "roves focus across day buttons with arrow keys (exactly one tabbable day)" do
    visit preview
    open_picker

    page.execute_script("document.querySelector('[role=grid] button[tabindex=\"0\"]').focus()")
    start_label = focused_day_label
    expect(start_label).to be_present, "grid should have exactly one tabbable day button"

    cdp_press("ArrowRight")
    after_right = focused_day_label
    expect(after_right).not_to eq(start_label), "ArrowRight should move focus to the next day"

    cdp_press("ArrowDown")
    expect(focused_day_label).not_to eq(after_right), "ArrowDown should move focus a week forward"

    tabbable = page.evaluate_script("document.querySelectorAll('[role=grid] button[tabindex=\"0\"]').length")
    expect(tabbable).to eq(1), "roving tabindex contract: exactly one tabbable day, got #{tabbable}"
  end

  # The example above roves from TODAY, so on the last days of a month its
  # ArrowDown target lies past the 42-cell grid. These two pin the APG rule
  # that makes it date-independent: an arrow that leaves the grid pages to
  # the adjacent month and lands on the same date there — it never dead-ends.
  it "ArrowDown from the last rendered day pages to the next month and lands a week later" do
    visit preview
    open_picker

    page.execute_script(<<~JS)
      const buttons = document.querySelectorAll('[role=grid] button[data-calendar-date-param]')
      const last = buttons[buttons.length - 1]
      buttons.forEach(b => b.tabIndex = -1); last.tabIndex = 0; last.focus()
    JS
    before_month = grid_month
    last_date = page.evaluate_script("document.activeElement.dataset.calendarDateParam")

    cdp_press("ArrowDown")

    expect(page).to have_css("[role=grid]:not([aria-label='#{before_month}'])")
    focused_date = page.evaluate_script("document.activeElement?.dataset?.calendarDateParam")
    expect(focused_date).to eq((Date.iso8601(last_date) + 7).iso8601),
      "ArrowDown from the last row lands on the same weekday a week later, in the next month"

    tabbable = page.evaluate_script("document.querySelectorAll('[role=grid] button[tabindex=\"0\"]').length")
    expect(tabbable).to eq(1), "roving tabindex contract survives the month change, got #{tabbable}"
  end

  it "ArrowLeft from the first rendered day pages to the previous month and lands a day earlier" do
    visit preview
    open_picker

    page.execute_script(<<~JS)
      const buttons = document.querySelectorAll('[role=grid] button[data-calendar-date-param]')
      const first = buttons[0]
      buttons.forEach(b => b.tabIndex = -1); first.tabIndex = 0; first.focus()
    JS
    before_month = grid_month
    first_date = page.evaluate_script("document.activeElement.dataset.calendarDateParam")

    cdp_press("ArrowLeft")

    expect(page).to have_css("[role=grid]:not([aria-label='#{before_month}'])")
    focused_date = page.evaluate_script("document.activeElement?.dataset?.calendarDateParam")
    expect(focused_date).to eq((Date.iso8601(first_date) - 1).iso8601),
      "ArrowLeft from the first cell lands on the previous day, in the previous month"
  end

  it "PageDown moves to the next month and keeps the grid's accessible name in sync" do
    visit preview
    open_picker

    page.execute_script("document.querySelector('[role=grid] button[tabindex=\"0\"]').focus()")
    before_month = grid_month
    cdp_press("PageDown")

    expect(page).to have_css("[role=grid]:not([aria-label='#{before_month}'])")
    expect(grid_month).not_to eq(before_month)
  end

  it "Escape closes the popover and returns focus to the trigger" do
    visit preview
    open_picker

    page.execute_script("document.querySelector('[role=grid] button[tabindex=\"0\"]').focus()")
    cdp_press("Escape")

    expect(page).to have_css("[data-date-picker-target='popover'][data-open='false']", visible: :all)
    expect(page.evaluate_script("document.activeElement === document.querySelector(#{trigger_selector.to_json})")).to(
      be(true), "APG dialog contract: Escape must return focus to the trigger, never strand it in a hidden subtree"
    )
  end

  it "activating a day selects it and reflects into the trigger label" do
    visit preview
    open_picker

    page.execute_script("document.querySelector('[role=grid] button[tabindex=\"0\"]').focus()")
    cdp_press("ArrowRight")
    selected_label = focused_day_label
    cdp_press("Enter")

    expect(page).to have_css("button[aria-pressed='true']", visible: :all)
    pressed = page.evaluate_script("document.querySelector('[role=grid] button[aria-pressed=\"true\"]')?.getAttribute('aria-label')")
    expect(pressed).to eq(selected_label)
  end
end
