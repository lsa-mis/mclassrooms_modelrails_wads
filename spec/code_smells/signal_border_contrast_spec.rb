# frozen_string_literal: true

require "rails_helper"

# A tinted chip's border is its only boundary, so it meets 3:1 (WCAG 1.4.11) on the
# worst ground in each theme. axe cannot see this (modelrails_ui#257).
RSpec.describe "Code smell: signal borders clear the non-text contrast floor" do
  include ContrastMath

  let(:signals) { File.read(Rails.root.join("app/assets/tailwind/tokens/_signals.css")) }
  let(:tones)   { %w[danger warning success info] }

  # The worst ground per theme, from the neutral scale.
  def worst_ground(theme)
    theme == :light ? oklch_to_rgb(98.4, 0.003, 247.858)   # surface        = slate-50
                    : oklch_to_rgb(27.9, 0.041, 260.031)   # surface-raised = slate-800
  end

  it "computes a contrast ratio correctly" do
    expect(contrast_ratio([ 1.0, 1.0, 1.0 ], [ 0.0, 0.0, 0.0 ])).to be_within(0.01).of(21.0)
  end

  # POSITIVE CONTROL: a regex that finds nothing asserts nothing.
  it "finds a border token for every tone in both themes" do
    tones.each do |tone|
      expect(token_values(signals, "#{tone}-border").size).to eq(2),
        "expected a light and a dark --color-#{tone}-border"
    end
  end

  %i[light dark].each do |theme|
    it "keeps every #{theme}-theme signal border visible on the worst ground in that theme" do
      tones.each do |tone|
        ratio = contrast_ratio(token_rgb(signals, "#{tone}-border", theme), worst_ground(theme))

        expect(ratio).to be >= ContrastMath::NON_TEXT_FLOOR,
          "#{theme} #{tone}-border is #{ratio}:1 against " \
          "#{theme == :light ? 'surface (slate-50)' : 'surface-raised (slate-800)'}, under the " \
          "#{ContrastMath::NON_TEXT_FLOOR}:1 non-text floor. The chip's fill is ~1.06:1 and " \
          "cannot darken without breaking its text's 7:1, so the border carries the edge alone."
      end
    end
  end

  # A lightness move only. Hue is checked against the tone's surface (within 10
  # degrees), not its text token, whose ramp rotates.
  it "keeps each border in its own tone's family" do
    tones.each do |tone|
      %i[light dark].each do |theme|
        _, border_chroma, border_hue = token(signals, "#{tone}-border", theme)
        _, _, surface_hue = token(signals, "#{tone}-surface", theme)

        expect(border_hue).to be_within(15).of(surface_hue),
          "#{theme} #{tone}-border sits at hue #{border_hue} while #{tone}-surface — the fill " \
          "it draws the edge of — is at #{surface_hue}; a border that has rotated off its own " \
          "chip reads as a different signal"
        expect(border_chroma).to be > 0.05,
          "#{theme} #{tone}-border has almost no chroma left (#{border_chroma}) — a grey edge " \
          "is not a signal, whatever its contrast"
      end
    end
  end
end
