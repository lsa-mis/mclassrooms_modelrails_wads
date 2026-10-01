# frozen_string_literal: true

require "rails_helper"

# Toast icons meet 3:1 (WCAG 1.4.11) on the inverting pill, computed from the
# shipped tokens (#1236).
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

  it "computes a contrast ratio correctly" do
    white = [ 1.0, 1.0, 1.0 ]
    black = [ 0.0, 0.0, 0.0 ]

    expect(contrast_ratio(white, black)).to be_within(0.01).of(21.0)
    expect(contrast_ratio(white, white)).to be_within(0.01).of(1.0)
  end

  # Light block first, dark second: asserted, since everything rests on it.
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
        ratio = contrast_ratio(token_rgb(signals, tone, theme),
                               token_rgb(signals, "#{tone}-surface", theme))

        expect(ratio).to be >= ContrastMath::NON_TEXT_FLOOR,
          "#{theme} #{tone} toast-card icon is #{ratio}:1 on #{tone}-surface, under the " \
          "#{ContrastMath::NON_TEXT_FLOOR}:1 non-text floor."
      end
    end
  end

  # On-toast tokens copy the OTHER theme's text value; asserted, since var() cannot.
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

  # The config is what reaches the view.
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
