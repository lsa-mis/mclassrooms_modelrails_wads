# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::IndicatorComponent, type: :component do
  it "wraps content in a relative inline-flex span" do
    render_inline(described_class.new) { "icon" }

    expect(page).to have_css("span.relative.inline-flex", visible: :all)
  end

  it "renders a count in a larger dot" do
    render_inline(described_class.new(count: 3)) { "icon" }

    expect(page).to have_css("span.size-5.min-w-5", text: "3", visible: :all)
  end

  it "renders a small dot without a count" do
    render_inline(described_class.new) { "icon" }

    expect(page).to have_css("span.size-2", visible: :all)
  end

  # Only AAA semantic tokens, never raw palette. Dots are SOLID fills (a dot must be a
  # visible graphic, so the tinted chip treatment would be invisible at dot size); the
  # count text uses the adaptive text-text-on-interactive token on EVERY level — warning
  # included (NOT the non-adaptive text-text-heading, which went low-contrast on the fill
  # in both themes).
  it "renders each signal variant with semantic tokens" do
    render_inline(described_class.new(variant: :info)) { "x" }
    expect(page).to have_css("span.bg-info.text-text-on-interactive", visible: :all)

    render_inline(described_class.new(variant: :success)) { "x" }
    expect(page).to have_css("span.bg-success.text-text-on-interactive", visible: :all)

    render_inline(described_class.new(variant: :warning)) { "x" }
    expect(page).to have_css("span.bg-warning.text-text-on-interactive", visible: :all)

    render_inline(described_class.new(variant: :danger)) { "x" }
    expect(page).to have_css("span.bg-danger.text-text-on-interactive", visible: :all)

    expect(page).not_to have_css("span.text-white", visible: :all)
    expect(page).not_to have_css("span.text-text-heading", visible: :all)
  end

  # `destructive` is a non-breaking alias for the canonical `danger`.
  it "renders the destructive alias as danger" do
    render_inline(described_class.new(variant: :destructive)) { "x" }

    expect(page).to have_css("span.bg-danger.text-text-on-interactive", visible: :all)
  end

  it "places the dot per the position keyword" do
    render_inline(described_class.new(position: :bottom_left)) { "x" }

    expect(page).to have_css("span.-bottom-1.-left-1", visible: :all)
  end

  it "raises on an unknown variant" do
    expect { described_class.new(variant: :nope) }.to raise_error(ArgumentError)
  end
end
