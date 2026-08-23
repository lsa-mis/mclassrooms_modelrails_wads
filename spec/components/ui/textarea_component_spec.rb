# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::TextareaComponent, type: :component do
  it "renders value as content and a11y params (builder-driven), with error-state chrome" do
    render_inline(described_class.new(
      name: "post[body]", value: "Hello", required: true, invalid: true, describedby: "post_body-error"
    ))

    ta = page.find("textarea")
    expect(ta.text.strip).to eq("Hello")
    expect(ta[:name]).to eq("post[body]")
    expect(ta["aria-required"]).to eq("true")
    expect(ta["aria-invalid"]).to eq("true")
    expect(ta["aria-describedby"]).to eq("post_body-error")
    expect(ta[:class]).to include("border-danger")
    expect(ta[:class]).not_to include("form-field")
  end

  it "uses the gem's base chrome and block content by default (standalone)" do
    render_inline(described_class.new(name: "q")) { "typed" }

    ta = page.find("textarea")
    expect(ta.text.strip).to eq("typed")
    expect(ta[:class]).to include("rounded-md", "border")
    expect(ta[:class]).not_to include("form-field")
    expect(ta["aria-invalid"]).to be_nil
  end
end
