# frozen_string_literal: true

require "rails_helper"

# Parity gate: UI::InputComponent must apply `.form-field`, which is the shared
# source of truth for field styling (defined in application.css). Error styling
# is attribute-driven via `.form-field[aria-invalid]`.
RSpec.describe UI::InputComponent, "field styling parity with TailwindFormBuilder", type: :component do
  it "applies the .form-field class in normal state" do
    render_inline(described_class.new(name: "user[name]"))
    cls = page.find("input")[:class]

    expect(cls).to include("form-field")
  end

  it "applies aria-invalid in error state so .form-field[aria-invalid] styling triggers" do
    render_inline(described_class.new(name: "user[name]", invalid: true))
    input = page.find("input")

    expect(input[:class]).to include("form-field")
    expect(input["aria-invalid"]).to eq("true")
  end
end
