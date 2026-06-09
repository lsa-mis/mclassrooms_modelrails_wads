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

  # The canonical `danger` signal uses the TINTED treatment (soft danger-surface +
  # saturated text-danger + danger-border), not a solid fill. text-danger on
  # bg-danger-surface is AAA-proven on the toast cards; never raw palette / text-white.
  # Focus is the uniform focus-ring outline (B5) — no per-tone danger ring.
  it "renders danger as a tinted danger surface (not text-white)" do
    render_inline(described_class.new("Error", variant: :danger))

    expect(page).to have_css("span.bg-danger-surface.text-danger.border-danger-border")
    expect(page).to have_css("span.focus-ring")
    expect(page).not_to have_css("span.text-white")
  end

  # `destructive` is a non-breaking alias for the canonical `danger`.
  it "renders the destructive alias as danger" do
    render_inline(described_class.new("Error", variant: :destructive))

    expect(page).to have_css("span.bg-danger-surface.text-danger.border-danger-border")
  end

  # Signal levels use the TINTED treatment (soft *-surface background + saturated
  # text-<level> + *-border), matching the alert + toast cards. The --color-<level>
  # base tokens are TEXT colors (dark in light mode), so a solid bg-<level> fill reads
  # as a muddy dark chip — e.g. bg-warning is amber-900 (a dark brown), nothing like
  # "warning." Only AAA semantic tokens, never raw palette.
  it "renders the signal levels with tinted semantic surfaces" do
    render_inline(described_class.new("Info", variant: :info))
    expect(page).to have_css("span.bg-info-surface.text-info.border-info-border")

    render_inline(described_class.new("Done", variant: :success))
    expect(page).to have_css("span.bg-success-surface.text-success.border-success-border")

    render_inline(described_class.new("Pending", variant: :warning))
    expect(page).to have_css("span.bg-warning-surface.text-warning.border-warning-border")

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
