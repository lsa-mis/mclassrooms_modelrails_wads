# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::InputComponent, type: :component do
  it "wires form + accessibility attributes from first-class params (standalone use)" do
    render_inline(described_class.new(
      type: "email",
      id: "user_email",
      name: "user[email]",
      value: "ada@example.com",
      required: true,
      invalid: true,
      describedby: "user_email_error"
    ))

    input = page.find("input")
    expect(input[:type]).to eq("email")
    expect(input[:id]).to eq("user_email")
    expect(input[:name]).to eq("user[email]")
    expect(input[:value]).to eq("ada@example.com")
    expect(input[:required]).to be_present
    expect(input["aria-required"]).to eq("true")
    expect(input["aria-invalid"]).to eq("true")
    expect(input["aria-describedby"]).to eq("user_email_error")
  end

  it "omits optional aria attributes when not provided (sensible default)" do
    render_inline(described_class.new(name: "q"))

    input = page.find("input")
    expect(input[:type]).to eq("text")
    expect(input["aria-invalid"]).to be_nil
    expect(input["aria-describedby"]).to be_nil
    expect(input["aria-required"]).to be_nil
  end
end
