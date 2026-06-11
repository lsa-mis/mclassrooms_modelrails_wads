# frozen_string_literal: true

require "rails_helper"

# Smoke test: the interactive playgrounds render without error in the preview host.
# Playgrounds render inline via @param-driven methods, so the gem's template-backed
# test excludes them — this is their only automated coverage. Guards the new
# playgrounds (sheet/device_mockup/stepper) and the two-axis refresh (button/badge:
# their default `cell` must be a proven variant/tone pair, not a fail-loud raise).
RSpec.describe "Component playgrounds render", type: :system do
  def visit_playground(component)
    visit "/rails/view_components/ui/#{component}_component/playground"
  end

  it "button playground renders a proven cell" do
    visit_playground("button")
    expect(page).to have_button("Button")
  end

  it "badge playground renders a proven cell" do
    visit_playground("badge")
    expect(page).to have_text("Badge")
  end

  it "stepper playground renders" do
    visit_playground("stepper")
    expect(page).to have_css("ol[aria-label]", visible: :all)
  end

  it "sheet playground renders" do
    visit_playground("sheet")
    expect(page).to have_css("dialog", visible: :all)
  end

  it "device_mockup playground renders" do
    visit_playground("device_mockup")
    expect(page).to have_text("Screen content")
  end

  it "input playground rewires ARIA from params" do
    visit "/rails/view_components/ui/input_component/playground?required=true&invalid=true"
    expect(page).to have_css('input[aria-invalid="true"][required]', visible: :all)
  end

  it "checkbox playground rewires aria-invalid from params" do
    visit "/rails/view_components/ui/checkbox_component/playground?invalid=true"
    expect(page).to have_css('input[type="checkbox"][aria-invalid="true"]', visible: :all)
  end

  it "radio_group playground rewires aria-invalid from params" do
    visit "/rails/view_components/ui/radio_group_component/playground?invalid=true"
    expect(page).to have_css('[role="radiogroup"][aria-invalid="true"]', visible: :all)
  end

  it "range playground renders with a live readout" do
    visit "/rails/view_components/ui/range_component/playground"
    expect(page).to have_css('input[type="range"]', visible: :all)
    expect(page).to have_css("output", visible: :all)
  end

  it "form_field playground rewires describedby/invalid from params" do
    visit "/rails/view_components/ui/form_field_component/playground?error=Required&required=true"
    expect(page).to have_css('input[aria-invalid="true"][aria-describedby*="error"][required]', visible: :all)
  end
end
