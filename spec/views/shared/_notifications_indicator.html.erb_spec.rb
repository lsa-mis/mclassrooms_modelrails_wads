require "rails_helper"

RSpec.describe "shared/_notifications_indicator.html.erb", type: :view do
  let(:render_indicator) do
    ->(summary:, surface: :avatar) do
      render partial: "shared/notifications_indicator", locals: { summary: summary, surface: surface }
    end
  end

  context "when summary[:severity] is nil (no unread)" do
    # v2 fade-out contract: the span ALWAYS renders so CSS opacity transitions
    # animate visibility changes. When summary[:severity] drops from danger to
    # nil (mark-all-read), the broadcast swap keeps the span in place and
    # opacity transitions from 100 to 0 over 150ms (motion-safe).
    before { render_indicator.call(summary: { count: 0, severity: nil }) }

    it "still renders the rounded-full span (stable DOM target for the opacity transition)" do
      expect(rendered).to match(/rounded-full/)
    end

    it "is opacity-0 so it is visually invisible" do
      expect(rendered).to match(/\bopacity-0\b/)
    end

    it "carries no data-severity attribute (no severity to expose)" do
      expect(rendered).not_to match(/data-severity=/)
    end

    it "carries no severity-colored bg class (no bg-danger-strong / bg-warning / bg-info)" do
      expect(rendered).not_to match(/bg-danger-strong/)
      expect(rendered).not_to match(/bg-warning\b/)
      expect(rendered).not_to match(/bg-info\b/)
    end

    it "does not pulse" do
      expect(rendered).not_to match(/animate-pulse/)
    end
  end

  describe "severity colors" do
    it "uses bg-danger-strong + motion-safe:animate-pulse + opacity-100 for :danger" do
      render_indicator.call(summary: { count: 1, severity: :danger })
      expect(rendered).to match(/bg-danger-strong/)
      expect(rendered).to match(/motion-safe:animate-pulse/)
      expect(rendered).to match(/\bopacity-100\b/)
    end

    it "uses bg-warning + opacity-100 and does NOT pulse for :warning" do
      render_indicator.call(summary: { count: 1, severity: :warning })
      expect(rendered).to match(/bg-warning(\b|")/)
      expect(rendered).not_to match(/animate-pulse/)
      expect(rendered).to match(/\bopacity-100\b/)
    end

    it "uses bg-info + opacity-100 and does NOT pulse for :info" do
      render_indicator.call(summary: { count: 1, severity: :info })
      expect(rendered).to match(/bg-info(\b|")/)
      expect(rendered).not_to match(/animate-pulse/)
      expect(rendered).to match(/\bopacity-100\b/)
    end
  end

  describe "structural classes" do
    before { render_indicator.call(summary: { count: 1, severity: :danger }) }

    it "is exactly w-2 h-2 (8px) — small enough to read as a dot, large enough to perceive at AAA luminance" do
      expect(rendered).to match(/\bw-2\b/)
      expect(rendered).to match(/\bh-2\b/)
    end

    it "is rounded-full" do
      expect(rendered).to match(/rounded-full/)
    end

    it "is absolutely positioned so the surrounding focusable button keeps its accessible name path clean (D1 lesson)" do
      expect(rendered).to match(/\babsolute\b/)
    end

    it "has aria-hidden=\"true\" — the dot is decorative; meaning lives in the user-menu Notifications row" do
      expect(rendered).to match(/aria-hidden="true"/)
    end

    it "has the drop-shadow halo for visibility on arbitrary backgrounds" do
      expect(rendered).to match(/drop-shadow/)
    end

    it "falls back to a visible mark in forced-colors mode (Windows High Contrast)" do
      expect(rendered).to match(/forced-colors:/)
    end

    it "has motion-safe transition for fade-out when count drops to zero" do
      expect(rendered).to match(/motion-safe:transition-opacity/)
    end
  end

  describe "surface positioning" do
    it "anchors at the avatar's bottom-right (matches D1 precedent for the bell glyph position)" do
      render_indicator.call(summary: { count: 1, severity: :danger }, surface: :avatar)
      expect(rendered).to match(/-bottom-0\.5/)
      expect(rendered).to match(/-right-0\.5/)
    end

    it "anchors at the hamburger button's top-right (matches the hamburger icon's visual centroid)" do
      render_indicator.call(summary: { count: 1, severity: :danger }, surface: :hamburger)
      expect(rendered).to match(/\btop-0\.5/)
      expect(rendered).to match(/\bright-0\.5/)
      expect(rendered).not_to match(/-bottom-0\.5/)
    end
  end
end
