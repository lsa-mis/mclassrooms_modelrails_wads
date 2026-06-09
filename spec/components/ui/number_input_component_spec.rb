# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::NumberInputComponent, type: :component do
  it "renders a number input" do
    render_inline(described_class.new(name: "qty"))

    expect(page).to have_css("input[type='number']")
  end

  # min / max / step / value pass straight through to the native attributes.
  it "passes native numeric attrs straight through" do
    render_inline(described_class.new(name: "qty", min: 0, max: 100, step: 5, value: 10))

    expect(page).to have_css("input[type='number'][min='0'][max='100'][step='5'][value='10']")
  end

  # AAA semantic tokens (the design-token guarantee), not raw colors:
  it "renders with AAA semantic tokens" do
    render_inline(described_class.new(name: "qty"))

    expect(page).to have_css("input.border-border-strong")
    expect(page).to have_css("input.focus-ring")
  end

  # 44px AAA touch target: the input carries the --form-input-height min-height token.
  it "meets the 44px touch target" do
    render_inline(described_class.new(name: "qty"))

    expect(page).to have_css('input.min-h-\\[var\\(--form-input-height\\)\\]')
  end

  # id-fallback: an id is always emitted so an external <label for=...> can target it.
  it "emits a fallback id even without id or name" do
    render_inline(described_class.new)

    input_id = page.find("input[type='number']")[:id]

    expect(input_id).not_to be_nil
    expect(input_id.to_s).not_to be_empty
  end

  it "uses the name as an id fallback" do
    render_inline(described_class.new(name: "order[qty]"))

    expect(page).to have_css("input[type='number'][id='order_qty_']")
  end

  it "lets an explicit id win" do
    render_inline(described_class.new(id: "my_qty", name: "qty"))

    expect(page).to have_css("input[type='number'][id='my_qty']")
  end

  # invalid: drives the server-validation-driven aria-invalid posture.
  it "sets aria-invalid when invalid" do
    render_inline(described_class.new(name: "qty", invalid: true))

    expect(page).to have_css("input[type='number'][aria-invalid='true']")
  end

  it "is not invalid by default" do
    render_inline(described_class.new(name: "qty"))

    expect(page).not_to have_css("input[aria-invalid='true']")
  end

  it "sets aria-describedby when describedby is given" do
    render_inline(described_class.new(name: "qty", describedby: "qty_error"))

    expect(page).to have_css("input[type='number'][aria-describedby='qty_error']")
  end

  it "omits aria-describedby by default" do
    render_inline(described_class.new(name: "qty"))

    expect(page).not_to have_css("input[aria-describedby]")
  end

  # required: sets the native HTML required AND aria-required.
  it "sets required and aria-required when required" do
    render_inline(described_class.new(name: "qty", required: true))

    expect(page).to have_css("input[type='number'][required][aria-required='true']")
  end

  it "is not required by default" do
    render_inline(described_class.new(name: "qty"))

    expect(page).not_to have_css("input[required]")
    expect(page).not_to have_css("input[aria-required]")
  end
end
