# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::CheckboxComponent, type: :component do
  it "renders a checkbox input" do
    render_inline(described_class.new(label: "Accept terms", name: "terms"))

    expect(page).to have_css("input[type='checkbox']")
  end

  # AAA semantic tokens (the design-token guarantee), not raw Tailwind:
  it "renders with AAA semantic tokens" do
    render_inline(described_class.new(label: "Accept terms", name: "terms"))

    expect(page).to have_css("input.border-border-strong")
    expect(page).to have_css("input.focus-ring")
    expect(page).to have_css('input.checked\\:bg-interactive')
  end

  # Label association: the <label for=...> targets the input's id.
  it "associates the label via for matching the input id" do
    render_inline(described_class.new(label: "Accept terms", name: "terms"))

    input_id = page.find("input[type='checkbox']")[:id]

    expect(input_id).not_to be_nil
    expect(page).to have_css("label[for='#{input_id}']", text: "Accept terms")
  end

  # Fallback id: with NEITHER id nor name, the input STILL has an id and the
  # label's `for` matches it (so the control is always labelled).
  it "associates the label even without an id or name" do
    render_inline(described_class.new(label: "Accept terms"))

    input_id = page.find("input[type='checkbox']")[:id]

    expect(input_id).not_to be_nil
    expect(input_id.to_s).not_to be_empty
    expect(page).to have_css("label[for='#{input_id}']", text: "Accept terms")
  end

  it "sets the checked attribute when checked" do
    render_inline(described_class.new(label: "Accept terms", name: "terms", checked: true))

    expect(page).to have_css("input[type='checkbox'][checked]")
  end

  # invalid: drives the server-validation-driven aria-invalid posture.
  it "sets aria-invalid when invalid" do
    render_inline(described_class.new(label: "Accept terms", name: "terms", invalid: true))

    expect(page).to have_css("input[type='checkbox'][aria-invalid='true']")
  end

  it "is not invalid by default" do
    render_inline(described_class.new(label: "Accept terms", name: "terms"))

    expect(page).not_to have_css("input[aria-invalid='true']")
  end

  it "sets aria-describedby when describedby is given" do
    render_inline(described_class.new(label: "Accept terms", name: "terms", describedby: "terms_error"))

    expect(page).to have_css("input[type='checkbox'][aria-describedby='terms_error']")
  end
end
