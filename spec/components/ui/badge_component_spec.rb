# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::BadgeComponent, type: :component do
  it "renders a span with the label by default" do
    render_inline(described_class.new("New"))

    expect(page).to have_css("span", text: "New")
  end

  # AAA semantic tokens (the design-token guarantee), not raw Tailwind:
  it "renders the default variant with AAA semantic tokens" do
    render_inline(described_class.new("New"))

    expect(page).to have_css("span.bg-interactive")
    expect(page).to have_css("span.text-text-on-interactive")
  end

  # Per-surface dark-AAA fix: destructive must use the adaptive
  # text-text-on-interactive token, NOT text-white (white-on-light-pink fails
  # AAA in dark mode).
  it "uses the adaptive on-interactive token for destructive (not text-white)" do
    render_inline(described_class.new("Error", variant: :destructive))

    expect(page).to have_css("span.bg-danger")
    expect(page).to have_css("span.text-text-on-interactive")
    expect(page).not_to have_css("span.text-white")
  end

  it "renders an anchor when href: is given" do
    render_inline(described_class.new("Docs", href: "/docs"))

    expect(page).to have_css("a[href='/docs']", text: "Docs")
  end

  # Fail-loud variant guard: an unknown variant raises in development/test.
  it "raises on an unknown variant" do
    expect {
      render_inline(described_class.new("X", variant: :bogus))
    }.to raise_error(ArgumentError)
  end
end
