# frozen_string_literal: true

require "rails_helper"

# The component specs assert the WIRING; these assert the wiring does something. Both
# behaviours here exist only because the DOM offers no declarative form of them —
# `indeterminate` is a property with no attribute, and an image 404 is only observable
# through an `error` event.
RSpec.describe "Small-wins behaviour", type: :system do
  describe "checkbox indeterminate" do
    before { visit "/rails/view_components/ui/checkbox_component/indeterminate" }

    def indeterminate?(name)
      page.evaluate_script(%{document.querySelector("input[name='#{name}']").indeterminate})
    end

    it "sets the DOM property the markup could not carry" do
      expect(indeterminate?("all")).to be(true)
    end

    # The control: a plain checkbox on the same page must NOT be indeterminate, so the
    # assertion above cannot pass by reading a default.
    it "leaves other checkboxes alone" do
      expect(indeterminate?("receipts")).to be(false)
    end

    it "clears the partial state once the user acts on it" do
      find("input[name='all']").click

      expect(indeterminate?("all")).to be(false)
    end
  end

  describe "avatar image failure" do
    before { visit "/rails/view_components/ui/avatar_component/broken_image" }

    it "replaces the broken image with the initials" do
      expect(page).to have_css("[data-avatar-target=fallback]", text: "DC")
    end

    # NOTE: the `error`-fires-before-connect race is NOT provable here. This page's
    # timing lets the event win every time, so any assertion written for it would pass
    # without the recovery code and prove nothing. It is proven in the gem's browser lane,
    # whose faster harness reproduces the failure naturally (modelrails_ui test/system).
    # A hidden-but-present <img> would keep announcing a picture that never arrived.
    it "removes the failed image entirely" do
      expect(page).to have_css("[data-avatar-target=fallback]", text: "DC")

      expect(page).to have_no_css("img", visible: :all)
    end
  end
end
