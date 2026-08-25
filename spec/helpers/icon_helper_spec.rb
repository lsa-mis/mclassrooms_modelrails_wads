require "rails_helper"

RSpec.describe IconHelper do
  before { IconRegistry.reload! }

  describe "#icon" do
    it "renders an svg element" do
      result = helper.icon(:check_circle)
      expect(result).to have_css("svg")
    end

    it "includes the SVG inner paths" do
      result = helper.icon(:check_circle)
      expect(result).to have_css("svg path")
    end

    it "sets the correct viewBox" do
      result = helper.icon(:check_circle)
      # Capybara/Nokogiri normalizes HTML attribute names to lowercase,
      # so viewBox becomes viewbox in the CSS selector
      expect(result).to have_css('svg[viewbox="0 0 24 24"]')
    end

    describe "sizes" do
      it "applies xs size classes" do
        result = helper.icon(:check_circle, size: :xs)
        expect(result).to have_css("svg.w-3.h-3")
      end

      it "applies sm size classes" do
        result = helper.icon(:check_circle, size: :sm)
        expect(result).to have_css("svg.w-4.h-4")
      end

      it "applies md size classes by default" do
        result = helper.icon(:check_circle)
        expect(result).to have_css("svg.w-5.h-5")
      end

      it "applies lg size classes" do
        result = helper.icon(:check_circle, size: :lg)
        expect(result).to have_css("svg.w-6.h-6")
      end

      it "applies xl size classes (#692: two views invented w-8 h-8 independently)" do
        result = helper.icon(:check_circle, size: :xl)
        expect(result).to have_css("svg.w-8.h-8")
      end
    end

    describe "styles" do
      it "sets outline attributes by default" do
        result = helper.icon(:check_circle)
        expect(result).to have_css('svg[fill="none"][stroke="currentColor"]')
      end

      it "sets solid attributes when requested" do
        result = helper.icon(:x_mark, style: :solid)
        expect(result).to have_css('svg[fill="currentColor"]')
        expect(result).not_to have_css("svg[stroke]")
      end
    end

    describe "custom classes" do
      it "merges custom classes with size classes" do
        result = helper.icon(:check_circle, class: "text-success-icon")
        expect(result).to have_css("svg.w-5.h-5.text-success-icon")
      end

      it "omits size classes when custom class includes w-* and h-*" do
        result = helper.icon(:check_circle, class: "w-8 h-8 text-info")
        expect(result).to have_css("svg.w-8.h-8.text-info")
        expect(result).not_to have_css("svg.w-5")
      end
    end

    describe "accessibility" do
      it "is decorative by default with aria-hidden" do
        result = helper.icon(:check_circle)
        expect(result).to have_css('svg[aria-hidden="true"]')
        expect(result).not_to have_css("svg[role]")
      end

      it "is meaningful when aria_label is provided" do
        result = helper.icon(:check_circle, aria_label: "Success")
        expect(result).to have_css('svg[role="img"][aria-label="Success"]')
        expect(result).not_to have_css("svg[aria-hidden]")
      end
    end

    describe "additional attributes" do
      it "passes data attributes through" do
        result = helper.icon(:sun, data: { theme_toggle_target: "lightIcon" })
        expect(result).to have_css('svg[data-theme-toggle-target="lightIcon"]')
      end
    end

    describe "unknown icons" do
      it "raises IconRegistry::NotFound" do
        expect { helper.icon(:nonexistent) }.to raise_error(IconRegistry::NotFound)
      end
    end
  end
end
