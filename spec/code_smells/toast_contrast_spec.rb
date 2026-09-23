# frozen_string_literal: true

require "rails_helper"

# Toast icons meet the 3:1 non-text floor (WCAG 1.4.11), computed from the
# shipped token values rather than eyeballed (#1236).
#
# Nothing else can see this — see ContrastMath for why. The pill is what makes
# it subtle: `--color-surface-toast` INVERTS (neutral-900 in the light theme,
# neutral-100 in the dark one), so a token tuned for the page's own ground is
# wrong on it by construction. The text already had `--color-text-on-toast` for
# that; the icon did not.
RSpec.describe "Code smell: toast icons clear the non-text contrast floor" do
  include ContrastMath

  let(:signals)  { File.read(Rails.root.join("app/assets/tailwind/tokens/_signals.css")) }
  let(:semantic) { File.read(Rails.root.join("app/assets/tailwind/tokens/_semantic.css")) }

  def page_rgb(theme)
    theme == :light ? oklch_to_rgb(98.4, 0.003, 247.858) : oklch_to_rgb(20.8, 0.042, 265.755)
  end

  # 90% opaque, so what an eye sees is the composite over the page.
  def pill_rgb(theme)
    raw = theme == :light ? [ 20.5, 0.016, 265.755 ] : [ 96.8, 0.007, 264.536 ]
    composite(oklch_to_rgb(*raw), 0.90, page_rgb(theme))
  end

  # A ratio computation that cannot fail is worth nothing.
  it "computes a contrast ratio correctly" do
    white = [ 1.0, 1.0, 1.0 ]
    black = [ 0.0, 0.0, 0.0 ]

    expect(contrast_ratio(white, black)).to be_within(0.01).of(21.0)
    expect(contrast_ratio(white, white)).to be_within(0.01).of(1.0)
  end

  # The light block is written first in these files, the dark block second.
  # Every other example rests on that, so it is asserted rather than assumed.
  it "reads the light theme's block before the dark one" do
    light = token(signals, "danger-surface", :light)
    dark  = token(signals, "danger-surface", :dark)

    expect(light.first).to be > dark.first,
      "danger-surface should be far lighter in the light theme; the token blocks may have " \
      "been reordered, which would silently invert every measurement in this file"
  end

  %i[light dark].each do |theme|
    it "keeps the #{theme}-theme pill's icons visible on the inverted surface" do
      %w[info success].each do |tone|
        ratio = contrast_ratio(token_rgb(semantic, "#{tone}-icon-on-toast", theme), pill_rgb(theme))

        expect(ratio).to be >= ContrastMath::NON_TEXT_FLOOR,
          "#{theme} #{tone} toast icon is #{ratio}:1 on the pill, under the " \
          "#{ContrastMath::NON_TEXT_FLOOR}:1 non-text floor. The pill inverts; the icon " \
          "token has to invert with it."
      end
    end

    it "keeps the #{theme}-theme card's icons visible on their own signal surface" do
      %w[warning danger].each do |tone|
        # The card's icon takes the tone's TEXT token, as the gem's alert does.
        ratio = contrast_ratio(token_rgb(signals, tone, theme),
                               token_rgb(signals, "#{tone}-surface", theme))

        expect(ratio).to be >= ContrastMath::NON_TEXT_FLOOR,
          "#{theme} #{tone} toast-card icon is #{ratio}:1 on #{tone}-surface, under the " \
          "#{ContrastMath::NON_TEXT_FLOOR}:1 non-text floor."
      end
    end
  end

  # The on-toast tokens hold a literal copy of the OTHER theme's signal text
  # value, because a var() cannot reach across theme blocks. That coupling is
  # invisible, so it is asserted rather than trusted to a comment.
  it "keeps each on-toast icon token equal to the opposite theme's signal text token" do
    { light: :dark, dark: :light }.each do |pill_theme, source_theme|
      %w[info success].each do |tone|
        expect(token(semantic, "#{tone}-icon-on-toast", pill_theme))
          .to eq(token(signals, tone, source_theme)),
            "--color-#{tone}-icon-on-toast in the #{pill_theme} block should mirror " \
            "--color-#{tone} from the #{source_theme} block — the pill inverts, so its " \
            "foreground comes from the other theme. Move them together."
      end
    end
  end

  # The config is what actually reaches the view; a correct token nobody
  # references fixes nothing.
  it "wires the pill tiers to the on-toast tokens and the card tiers to the text tokens" do
    Rails.application.config.toasts[:types].each do |name, config|
      if config[:tier] == :pill
        expect(config[:icon_color]).to match(/-icon-on-toast\z/),
          "#{name} is a pill, so its icon must use an -on-toast token, not #{config[:icon_color]}"
      else
        expect(config[:icon_color]).not_to match(/-icon\z/),
          "#{name} is a card on a tinted signal surface; #{config[:icon_color]} measured under " \
          "the non-text floor there. Use the tone's text token."
      end
    end
  end
end
