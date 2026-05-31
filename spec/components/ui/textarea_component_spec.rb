# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::TextareaComponent, type: :component do
  it "renders app field styling, value as content, and a11y params (builder-driven)" do
    render_inline(described_class.new(
      name: "post[body]", value: "Hello", required: true, invalid: true, describedby: "post_body-error"
    ))

    ta = page.find("textarea")
    expect(ta.text.strip).to eq("Hello") # textarea carries a leading newline by spec (Rails parity)
    expect(ta[:name]).to eq("post[body]")
    expect(ta["aria-required"]).to eq("true")
    expect(ta["aria-invalid"]).to eq("true")
    expect(ta["aria-describedby"]).to eq("post_body-error")
    expect(ta[:class]).to include("min-h-[var(--form-input-height)]")
    expect(ta[:class]).to include("bg-danger-surface") # error state matches FIELD_ERROR
  end

  it "uses normal styling and block content by default (standalone)" do
    render_inline(described_class.new(name: "q")) { "typed" }

    ta = page.find("textarea")
    expect(ta.text.strip).to eq("typed")
    expect(ta[:class]).to include("border-border-strong")
    expect(ta["aria-invalid"]).to be_nil
  end
end
