# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the combobox component (scoped to its visible root;
# axe skips any hidden popover by design). No color-contrast exclude.
RSpec.describe "Combobox component accessibility", type: :system do
  it "default passes AAA in both themes" do
    visit "/rails/view_components/ui/combobox_component/default"

    expect(page).to have_css("[role='combobox']")

    scope = [ "[data-controller='combobox']" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  # Characterization net over combobox_controller.js's keyboard contract
  # (fizzy adoption plan rev 3, Task B): the six handled keys
  # (Escape/↓/↑/Home/End/Enter), aria-activedescendant movement, and the
  # filtered-list first-match reset. These pin EXISTING behavior — a red here
  # is a finding to triage, never an expectation to edit into agreement.
  # Preview options: United States/Canada/Mexico/Brazil/Argentina.
  describe "keyboard contract" do
    before { visit "/rails/view_components/ui/combobox_component/default" }

    def input
      find("[role='combobox']")
    end

    def active_option_text
      page.evaluate_script(<<~JS)
        (() => {
          const id = document.querySelector("[role='combobox']").getAttribute("aria-activedescendant");
          return id ? document.getElementById(id).textContent.trim() : null;
        })()
      JS
    end

    it "opens on focus with the first option active (activedescendant, not DOM focus)" do
      input.click

      expect(input["aria-expanded"]).to eq("true")
      expect(page).to have_css("[data-combobox-target='panel']:not([hidden])")
      expect(active_option_text).to eq("United States")
      # DOM focus stays on the input — the APG combobox pattern.
      expect(page.evaluate_script("document.activeElement.getAttribute('role')")).to eq("combobox")
    end

    it "moves the active option with ArrowDown/ArrowUp, wrapping at both ends" do
      input.click # active: United States

      cdp_press(:down)
      expect(active_option_text).to eq("Canada")

      cdp_press(:up)
      expect(active_option_text).to eq("United States")

      cdp_press(:up) # wraps backward from the first option
      expect(active_option_text).to eq("Argentina")

      cdp_press(:down) # wraps forward from the last option
      expect(active_option_text).to eq("United States")
    end

    it "jumps to the last visible option on End and the first on Home" do
      input.click

      cdp_press(:end)
      expect(active_option_text).to eq("Argentina")

      cdp_press(:home)
      expect(active_option_text).to eq("United States")
    end

    it "selects the active option on Enter: commits the hidden value and closes" do
      input.click
      cdp_press(:down) # Canada
      cdp_press(:enter)

      expect(input["aria-expanded"]).to eq("false")
      expect(input.value).to eq("Canada")
      expect(find("input[name='country']", visible: :all).value).to eq("ca")
      expect(page).to have_css(
        "[data-combobox-target='option'][data-combobox-value='ca'][aria-selected='true']",
        visible: :all
      )
    end

    it "closes on Escape, clearing the active option and an uncommitted query" do
      input.click
      cdp_press(:escape)

      expect(input["aria-expanded"]).to eq("false")
      expect(page).to have_css("[data-combobox-target='panel'][hidden]", visible: :all)
      expect(active_option_text).to be_nil
      expect(input.value).to eq("") # nothing committed — input restored to blank
    end

    it "restores the committed label when Escape abandons a filter query" do
      input.click
      cdp_press(:down) # Canada
      cdp_press(:enter) # commit Canada

      input.click # reopen
      cdp_browser.keyboard.type("Mex") # uncommitted filter text
      cdp_press(:escape)

      expect(input.value).to eq("Canada")
      expect(find("input[name='country']", visible: :all).value).to eq("ca")
    end

    it "reopens a closed listbox on ArrowDown, activating the first option" do
      input.click
      cdp_press(:escape)
      cdp_press(:down)

      expect(input["aria-expanded"]).to eq("true")
      expect(active_option_text).to eq("United States")
    end

    it "reopens a closed listbox on ArrowUp, activating the LAST option (#661)" do
      input.click
      cdp_press(:escape)
      cdp_press(:up)

      expect(input["aria-expanded"]).to eq("true")
      expect(active_option_text).to eq("Argentina")
    end

    it "filters to matching options and re-activates the first visible match" do
      input.click
      cdp_browser.keyboard.type("br")

      expect(page).to have_css("[data-combobox-target='option']:not([hidden])", count: 1)
      expect(page).to have_css("[data-combobox-target='option']:not([hidden])", text: "Brazil")
      expect(active_option_text).to eq("Brazil")
      expect(page).to have_css("[data-combobox-target='empty'][hidden]", visible: :all)
    end

    it "shows the empty state and clears the active option when nothing matches" do
      input.click
      cdp_browser.keyboard.type("zz")

      expect(page).to have_css("[data-combobox-target='empty']:not([hidden])")
      expect(page).not_to have_css("[data-combobox-target='option']:not([hidden])")
      expect(active_option_text).to be_nil
    end
  end
end
