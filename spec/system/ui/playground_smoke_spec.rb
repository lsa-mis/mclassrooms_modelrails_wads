# frozen_string_literal: true

require "rails_helper"

# Smoke test: the new interactive playgrounds render without error in the preview host
# (playgrounds render inline via @param-driven methods, so no other test covers them).
RSpec.describe "Component playgrounds render", type: :system do
  {
    "stepper" => "ol[aria-label]",
    "sheet" => "dialog",
    "device_mockup" => "div"
  }.each do |component, selector|
    it "#{component} playground renders its component" do
      visit "/rails/view_components/ui/#{component}_component/playground"
      expect(page).to have_css(selector, visible: :all)
    end
  end
end
