# frozen_string_literal: true

require "rails_helper"

# APG tabs: which arrow keys navigate follows `aria-orientation`, and `activation:`
# decides whether moving focus also reveals the panel. Base shipped automatic +
# horizontal only; both remain the defaults, so existing call sites are unaffected.
RSpec.describe "Tabs keyboard model", type: :system do
  def press(key) = page.driver.browser.keyboard.type(key)
  def selected = page.find("[role=tab][aria-selected=true]").text
  def focused = page.evaluate_script("document.activeElement.textContent.trim()")

  describe "horizontal + automatic (the defaults)" do
    before do
      visit "/rails/view_components/ui/tabs_component/basic"
      find("[role=tab]", text: "Profile").click
    end

    it "moves and activates with ArrowRight" do
      press(:Right)

      expect(selected).to eq("Password")
    end

    # The control that proves the vertical case below is not vacuous.
    it "ignores ArrowDown" do
      press(:Down)

      expect(selected).to eq("Profile")
    end
  end

  describe "vertical" do
    before do
      visit "/rails/view_components/ui/tabs_component/vertical"
      find("[role=tab]", text: "Profile").click
    end

    it "moves and activates with ArrowDown" do
      press(:Down)

      expect(selected).to eq("Password")
    end

    it "ignores ArrowRight" do
      press(:Right)

      expect(selected).to eq("Profile")
    end
  end

  describe "manual activation" do
    before do
      visit "/rails/view_components/ui/tabs_component/manual"
      find("[role=tab]", text: "Profile").click
    end

    it "moves focus without revealing the panel" do
      press(:Right)

      expect(focused).to eq("Password")
      expect(selected).to eq("Profile")
    end

    it "reveals the focused panel on Enter" do
      press(:Right)
      press(:Enter)

      expect(selected).to eq("Password")
    end
  end
end
