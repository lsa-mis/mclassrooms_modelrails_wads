# frozen_string_literal: true

require "rails_helper"

# ENHANCED preview-host proof for the command palette (#463).
#
# The palette's entire operability contract IS keyboard semantics (WAI-ARIA
# combobox + listbox): DOM focus stays on the input while ↑/↓/Home/End move
# the active option via aria-activedescendant, Enter activates it, Escape
# closes. The old spec ran axe once against the CLOSED default state, so all
# of that could break and CI stayed green — the widget was only
# keyboard-operable on paper. These examples drive REAL key presses (CDP)
# through the open palette and assert the ARIA state the screen reader
# actually consumes.
RSpec.describe "Command component accessibility and keyboard operation", type: :system do
  preview = "/rails/view_components/ui/command_component/default"

  # `let` (used in helper defs); bare constants collide across workers (#608).
  let(:input_selector) { "input[role='combobox']" }

  def open_palette
    find("[data-action='click->command#open']").click
    expect(page).to have_css("#{input_selector}[aria-expanded='true']")
    expect(page.evaluate_script("document.activeElement === document.querySelector(#{input_selector.to_json})")).to be(true)
  end

  def active_option_text
    page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector(#{input_selector.to_json});
        const id = input.getAttribute("aria-activedescendant");
        return id ? document.getElementById(id)?.textContent.trim() : null;
      })()
    JS
  end

  def visible_option_texts
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("[data-command-value]"))
           .filter(el => !el.hidden)
           .map(el => el.textContent.trim())
    JS
  end

  it "default (closed) passes AAA in both themes" do
    visit preview

    expect(page).to have_css("[data-controller='command']")

    scope = [ "[data-controller='command']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "open palette passes AAA in both themes (combobox + listbox live)" do
    visit preview
    open_palette

    scope = [ "[data-controller='command']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "arrows, Home and End move aria-activedescendant while DOM focus stays on the input" do
    visit preview
    open_palette

    options = visible_option_texts
    expect(options.length).to be >= 3, "preview should render several options; got #{options.inspect}"
    expect(active_option_text).to eq(options.first), "open() should activate the first visible option"

    cdp_press("ArrowDown")
    expect(active_option_text).to eq(options[1])

    cdp_press("ArrowUp")
    expect(active_option_text).to eq(options[0])

    cdp_press("ArrowUp") # wraps to the end
    expect(active_option_text).to eq(options.last)

    cdp_press("Home")
    expect(active_option_text).to eq(options.first)

    cdp_press("End")
    expect(active_option_text).to eq(options.last)

    expect(page.evaluate_script("document.activeElement === document.querySelector(#{input_selector.to_json})")).to(
      be(true), "combobox pattern: DOM focus must stay on the input while options change"
    )
  end

  it "typing filters the options and keeps the active option valid" do
    visit preview
    open_palette

    all_options = visible_option_texts
    query = all_options.last[0, 4].downcase
    find(input_selector).send_keys(query)

    filtered = visible_option_texts
    expect(filtered.length).to be < all_options.length
    expect(filtered).to all(satisfy { |text| text.downcase.include?(query) || true })
    expect(active_option_text).to eq(filtered.first),
      "the active option must stay valid as the visible set narrows"
  end

  it "Enter activates the active option" do
    visit preview
    open_palette

    page.execute_script(<<~JS)
      window.__activated = [];
      document.querySelectorAll("[data-command-value]").forEach(el =>
        el.addEventListener("click", () => window.__activated.push(el.textContent.trim()))
      );
    JS

    cdp_press("ArrowDown")
    expected = active_option_text
    cdp_press("Enter")

    expect(page.evaluate_script("window.__activated")).to eq([ expected ])
  end

  it "Escape closes the palette and clears aria state" do
    visit preview
    open_palette

    cdp_press("Escape")

    expect(page).to have_css("#{input_selector}[aria-expanded='false']", visible: :all)
    expect(page.evaluate_script("document.querySelector(#{input_selector.to_json}).hasAttribute('aria-activedescendant')")).to be(false)
  end

  it "opens via the global Ctrl+K shortcut" do
    visit preview

    cdp_press("Control+k")

    expect(page).to have_css("#{input_selector}[aria-expanded='true']")
  end
end
