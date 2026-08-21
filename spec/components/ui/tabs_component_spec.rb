# frozen_string_literal: true

require "rails_helper"

# APG tabs allow two activation models and two orientations. Base shipped only automatic
# + horizontal; both are still the defaults, so existing call sites render unchanged.
RSpec.describe UI::TabsComponent, type: :component do
  def tabs(**opts)
    render_inline(described_class.new(label: "Sections", **opts)) do |c|
      c.with_tab(title: "One") { "First" }
      c.with_tab(title: "Two") { "Second" }
    end
  end

  describe "orientation" do
    it "declares horizontal by default" do
      tabs

      expect(page).to have_css("[role=tablist][aria-orientation=horizontal]", visible: :all)
    end

    it "declares vertical when asked" do
      tabs(orientation: :vertical)

      expect(page).to have_css("[role=tablist][aria-orientation=vertical]", visible: :all)
    end

    # The controller reads this to decide which arrow keys navigate.
    it "tells the controller which orientation it is in" do
      tabs(orientation: :vertical)

      expect(page).to have_css("[data-tabs-orientation-value=vertical]", visible: :all)
    end

    it "rejects an unknown orientation" do
      expect { tabs(orientation: :diagonal) }.to raise_error(ArgumentError, /orientation/)
    end
  end

  describe "activation" do
    it "is automatic by default" do
      tabs

      expect(page).to have_css("[data-tabs-activation-value=automatic]", visible: :all)
    end

    it "can be manual" do
      tabs(activation: :manual)

      expect(page).to have_css("[data-tabs-activation-value=manual]", visible: :all)
    end

    it "rejects an unknown activation mode" do
      expect { tabs(activation: :telepathic) }.to raise_error(ArgumentError, /activation/)
    end
  end
end
