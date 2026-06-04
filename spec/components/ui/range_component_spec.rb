# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::RangeComponent, type: :component do
  it "renders a native range input with min/max/step" do
    render_inline(described_class.new(min: 0, max: 10, step: 2))

    expect(page).to have_css("input[type='range'][min='0'][max='10'][step='2']")
  end

  it "emits the value when supplied" do
    render_inline(described_class.new(value: 7))

    expect(page).to have_css("input[type='range'][value='7']")
  end

  it "omits the value when nil" do
    render_inline(described_class.new)

    expect(page).not_to have_css("input[type='range'][value]")
  end

  # AAA semantic token (the design-token guarantee), not raw Tailwind:
  it "renders with the AAA semantic token" do
    render_inline(described_class.new)

    expect(page).to have_css("input.accent-interactive")
  end

  it "sets aria-invalid when invalid" do
    render_inline(described_class.new(invalid: true))

    expect(page).to have_css("input[type='range'][aria-invalid='true']")
  end

  it "omits aria-invalid when not invalid" do
    render_inline(described_class.new)

    expect(page).not_to have_css("input[type='range'][aria-invalid]")
  end

  it "sets aria-describedby when describedby is given" do
    render_inline(described_class.new(describedby: "volume-help"))

    expect(page).to have_css("input[type='range'][aria-describedby='volume-help']")
  end

  it "omits aria-describedby by default" do
    render_inline(described_class.new)

    expect(page).not_to have_css("input[type='range'][aria-describedby]")
  end

  it "uses the explicit id attribute" do
    render_inline(described_class.new(id: "my_range"))

    expect(page).to have_css("input#my_range")
  end

  it "falls back to the name for the id" do
    render_inline(described_class.new(name: "post[volume]"))

    expect(page).to have_css("input#post_volume_")
  end

  it "always emits an id with neither id nor name" do
    render_inline(described_class.new)

    expect(page).to have_css("input[type='range'][id]")
  end

  # --- show_value: opt-in <output> readout (STRUCTURE) ---
  # The live readout sync (drag the slider -> <output> text updates) is verified by
  # the 0b browser spec, not here — the render harness has no JS runtime, so we
  # assert the wiring (data-controller / data-action / targets) the `range`
  # Stimulus controller hooks into, not the runtime behavior.

  it "wraps the input in the range controller when show_value is true" do
    render_inline(described_class.new(show_value: true))

    expect(page).to have_css("div[data-controller='range'] input[type='range']")
  end

  it "wires the input target and sync action when show_value is true" do
    render_inline(described_class.new(show_value: true))

    expect(page).to have_css("input[data-range-target='input'][data-action~='input->range#sync']")
  end

  it "renders an output targeting the input id with the AAA token" do
    render_inline(described_class.new(id: "vol", value: 60, show_value: true))

    expect(page).to have_css("output[for='vol'][data-range-target='output'].text-text-body", text: "60")
  end

  it "uses the native midpoint for the output when value is nil" do
    render_inline(described_class.new(min: 0, max: 100, show_value: true))

    expect(page).to have_css("output[data-range-target='output']", text: "50")
  end

  # Default (show_value omitted) is byte-unchanged: no wrapper, no output.
  it "omits the output and range controller by default" do
    render_inline(described_class.new)

    expect(page).not_to have_css("[data-controller='range']")
    expect(page).not_to have_css("output")
  end
end
