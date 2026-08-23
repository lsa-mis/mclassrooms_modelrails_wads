# frozen_string_literal: true

require "rails_helper"

# The three sidebar behaviours that only a browser can prove: the toggle's state is
# exposed to assistive tech, the collapsed rail explains its icons, and the collapse
# choice survives navigation.
RSpec.describe "Sidebar behaviours", type: :system do
  def toggle = find("aside button[aria-controls]")

  describe "collapse state is exposed to assistive technology" do
    # data-collapsed drives the CSS but is invisible to a screen reader. Without
    # aria-expanded the toggle announces no state and pressing it announces no change.
    it "reports expanded when open and collapsed when closed" do
      visit "/rails/view_components/ui/sidebar_component/default"

      expect(toggle["aria-expanded"]).to eq("true")

      toggle.click

      expect(toggle["aria-expanded"]).to eq("false")
    end

    it "starts collapsed when the component is rendered collapsed" do
      visit "/rails/view_components/ui/sidebar_component/collapsed"

      expect(toggle["aria-expanded"]).to eq("false")
    end

    it "points aria-controls at the nav it collapses" do
      visit "/rails/view_components/ui/sidebar_component/default"

      expect(page).to have_css("aside nav##{toggle['aria-controls']}")
    end
  end

  describe "the collapsed rail explains its icons" do
    before { visit "/rails/view_components/ui/sidebar_component/collapsed" }

    # The label text is clipped to width 0 but stays in the accessibility tree, so the
    # link already has its name. The bubble is therefore decorative — announcing it too
    # would name every item twice.
    it "hides the bubble from assistive technology" do
      expect(page).to have_css("aside [data-slot=rail-tooltip][aria-hidden=true]", visible: :all)
    end

    it "reveals the bubble on focus" do
      expect(bubble_opacity).to eq(0.0)

      first("aside nav a").execute_script("this.focus()")

      # It fades in, so settle rather than reading mid-transition.
      expect(settled_bubble_opacity).to eq(1.0)
    end

    # The nav is a scroll container (overflow-y:auto makes overflow-x non-visible too), so
    # an absolutely-positioned bubble is clipped at the 64px rail edge. `fixed` is what
    # escapes it. This has to assert the computed position, not just geometry:
    # getBoundingClientRect reports the *unclipped* box either way, so a geometry-only
    # check would pass just as happily on the broken version.
    it "escapes the rail's scroll container rather than being clipped inside it" do
      first("aside nav a").execute_script("this.focus()")
      geometry = page.evaluate_script(<<~JS)
        (() => {
          const bubble = document.querySelector("aside nav a [data-slot=rail-tooltip]")
          return {
            position: getComputedStyle(bubble).position,
            navClipsX: getComputedStyle(document.querySelector("aside nav")).overflowX !== "visible",
            bubbleRight: bubble.getBoundingClientRect().right,
            railRight: document.querySelector("aside").getBoundingClientRect().right
          }
        })()
      JS

      expect(geometry["navClipsX"]).to be(true)
      expect(geometry["position"]).to eq("fixed")
      expect(geometry["bubbleRight"]).to be > geometry["railRight"]
    end
  end

  describe "the collapse choice survives navigation" do
    it "records the choice in a cookie the server can read" do
      visit "/rails/view_components/ui/sidebar_component/default"
      toggle.click

      expect(cookie_named("sidebar_collapsed")).to eq("true")

      toggle.click

      expect(cookie_named("sidebar_collapsed")).to eq("false")
    end

    it "does not write a cookie when remembering is off" do
      visit "/rails/view_components/ui/sidebar_component/not_remembered"
      toggle.click

      expect(cookie_named("sidebar_collapsed")).to be_nil
    end
  end

  # Polls until the fade finishes. Returns the last value either way, so a bubble that
  # never appears fails on its actual opacity rather than on a timeout.
  def settled_bubble_opacity
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time
    value = bubble_opacity
    value = bubble_opacity while value < 1.0 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    value
  end

  def bubble_opacity
    page.evaluate_script(
      %{getComputedStyle(document.querySelector("aside nav a [data-slot=rail-tooltip]")).opacity}
    ).to_f
  end

  def cookie_named(name)
    page.driver.browser.cookies.all[name]&.value
  end
end
