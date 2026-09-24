# frozen_string_literal: true

require "rails_helper"

# A tinted chip's BORDER is the only boundary it has, so it answers to the 3:1
# non-text floor (WCAG 1.4.11).
#
# The fill cannot do this job. A chip's surface measures ~1.06:1 against the
# page, and it cannot be darkened, because its own text has to hold 7:1 against
# it — the darkest tint that still does reaches only 1.09-1.29:1. So an alert,
# banner, toast, badge or error summary is either outlined or it is a floating
# block of tinted text (modelrails_ui#257).
#
# Each value is solved against the WORST ground in its theme rather than the
# convenient one: `surface` in light, `surface-raised` in dark. Solving against
# white and against the dark page instead produces values that pass on the page
# and fail inside a card — which is how they would be met in practice.
#
# Nothing else can see this. See ContrastMath: axe measures text only, and the
# component specs assert class names, not values.
RSpec.describe "Code smell: signal borders clear the non-text contrast floor" do
  include ContrastMath

  let(:signals) { File.read(Rails.root.join("app/assets/tailwind/tokens/_signals.css")) }
  let(:tones)   { %w[danger warning success info] }

  # The worst ground each theme's border has to survive, resolved from the
  # neutral scale the semantic surfaces alias.
  def worst_ground(theme)
    theme == :light ? oklch_to_rgb(98.4, 0.003, 247.858)   # surface        = slate-50
                    : oklch_to_rgb(27.9, 0.041, 260.031)   # surface-raised = slate-800
  end

  it "computes a contrast ratio correctly" do
    expect(contrast_ratio([ 1.0, 1.0, 1.0 ], [ 0.0, 0.0, 0.0 ])).to be_within(0.01).of(21.0)
  end

  # Every assertion below loops over what a regex found, and a regex that finds
  # nothing asserts nothing.
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

  # The repositioning is a LIGHTNESS move. If a later edit also shifts hue the
  # chip changes character, which is a design decision rather than a contrast
  # fix — it should be made deliberately, not arrive inside one.
  #
  # Measured against the tone's own SURFACE, not its text token. Those are the
  # two colours physically adjacent on a chip, and they track each other within
  # 10 degrees. The text token is the far end of the same ramp and is not a
  # useful neighbour: light `warning` sits 40 degrees from its border, because
  # amber's hue genuinely rotates from ~46 at the 900 step to ~96 at the 50.
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
