# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::FileInputComponent, type: :component do
  it "renders the app's file-field styling + a11y params" do
    render_inline(described_class.new(
      name: "user[avatar]", accept: "image/*", invalid: true, describedby: "user_avatar-error"
    ))

    inp = page.find("input[type=file]")
    expect(inp[:name]).to eq("user[avatar]")
    expect(inp[:accept]).to eq("image/*")
    expect(inp["aria-invalid"]).to eq("true")
    expect(inp["aria-describedby"]).to eq("user_avatar-error")
    expect(inp[:class]).to include("file:bg-interactive")
    expect(inp[:class]).to include("file:min-h-[var(--form-input-height)]")
  end
end
