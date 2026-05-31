# frozen_string_literal: true

require "rails_helper"

# Parity gate: UI::InputComponent must render the SAME field styling the app's
# TailwindFormBuilder produces today, so swapping it in is invisible.
# Source of truth: TailwindFormBuilder::FIELD_BASE / FIELD_NORMAL / FIELD_ERROR.
RSpec.describe UI::InputComponent, "field styling parity with TailwindFormBuilder", type: :component do
  it "matches the app's normal-state field styling" do
    render_inline(described_class.new(name: "user[name]"))
    cls = page.find("input")[:class]

    expect(cls).to include("min-h-[var(--form-input-height)]") # shared field-height token
    expect(cls).to include("border-border-strong")
    expect(cls).to include("bg-surface-raised")
    expect(cls).to include("focus:ring-2")
    expect(cls).to include("focus:ring-interactive-focus")
  end

  it "matches the app's error-state field styling when invalid" do
    render_inline(described_class.new(name: "user[name]", invalid: true))
    cls = page.find("input")[:class]

    expect(cls).to include("bg-danger-surface")
    expect(cls).to include("text-danger")
    expect(cls).to include("ring-danger")
  end
end
