# frozen_string_literal: true

require "rails_helper"

# Every syntax colour clears 7:1 on every code-block ground in both themes, from the tokens:
# docs_spec's axe run sees only the tokens its page contains, and missed --syntax-prompt.
RSpec.describe "Code smell: syntax highlighting clears AAA text contrast" do
  include ContrastMath

  let(:syntax)  { File.read(Rails.root.join("app/assets/tailwind/_syntax.css")) }
  let(:signals) { File.read(Rails.root.join("app/assets/tailwind/tokens/_signals.css")) }

  # Tailwind v4 slate, which the neutral primitives point at (_primitives.css).
  def slate(shade)
    {
      50 => [ 98.4, 0.003, 247.858 ], 100 => [ 96.8, 0.007, 247.896 ], 300 => [ 86.9, 0.022, 252.894 ],
      500 => [ 55.4, 0.046, 257.417 ], 600 => [ 44.6, 0.043, 257.281 ], 700 => [ 37.2, 0.044, 257.287 ],
      800 => [ 27.9, 0.041, 260.031 ], 900 => [ 20.8, 0.042, 265.755 ]
    }.fetch(shade)
  end

  # Painted on no glyph: `.w` colours whitespace, and the -bg tokens are grounds.
  let(:not_text) { %w[whitespace error-bg insert-bg] }

  def block(theme)
    theme == :light ? syntax[/^:root \{.*?^\}/m] : syntax[/^\.dark \{.*?^\}/m]
  end

  def syntax_tokens(theme)
    block(theme).scan(/--syntax-([\w-]+):\s*([^;]+);/).to_h { |name, raw| [ name, raw.strip ] }
  end

  def rgb(raw)
    case raw
    when /\Aoklch\(([\d.]+)%\s+([\d.]+)\s+([\d.]+)\)\z/ then oklch_to_rgb($1.to_f, $2.to_f, $3.to_f)
    when /\Avar\(--neutral-(\d+)\)\z/ then oklch_to_rgb(*slate($1.to_i))
    when "transparent" then nil
    else raise ArgumentError, "unrecognised syntax token value #{raw.inspect}"
    end
  end

  # `.highlight` sits on bg-surface; `.hll` lifts a line onto warning-surface;
  # deletions and insertions paint their own ground where the theme sets one.
  def grounds(theme)
    tokens = syntax_tokens(theme)
    {
      "surface" => oklch_to_rgb(*slate(theme == :light ? 50 : 900)),
      "warning-surface (.hll)" => token_rgb(signals, "warning-surface", theme),
      "error-bg" => rgb(tokens.fetch("error-bg")),
      "insert-bg" => rgb(tokens.fetch("insert-bg"))
    }.compact
  end

  %i[light dark].each do |theme|
    it "reads a full #{theme}-theme syntax palette" do
      expect(syntax_tokens(theme).keys).to include("comment", "keyword", "string", "prompt"),
        "the #{theme} block no longer yields the syntax tokens; every assertion below would pass on nothing"
    end

    it "keeps every #{theme}-theme syntax colour at AAA on every code-block ground" do
      failures = syntax_tokens(theme).except(*not_text).flat_map do |name, raw|
        grounds(theme).filter_map do |ground, ground_rgb|
          ratio = contrast_ratio(rgb(raw), ground_rgb)
          "--syntax-#{name} on #{ground}: #{ratio}:1" if ratio < ContrastMath::AAA_TEXT_FLOOR
        end
      end

      expect(failures).to be_empty,
        "#{theme}-theme syntax colours under #{ContrastMath::AAA_TEXT_FLOOR}:1:\n  #{failures.join("\n  ")}"
    end
  end
end
