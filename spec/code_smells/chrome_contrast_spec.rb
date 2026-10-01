# frozen_string_literal: true

require "rails_helper"

# A fork that brands the header sets the whole chrome family in _brand.css; measured here.
RSpec.describe "Code smell: a branded header clears the contrast floors" do
  include ContrastMath

  let(:brand)    { File.read(Rails.root.join("app/assets/tailwind/tokens/_brand.css")) }
  let(:semantic) { File.read(Rails.root.join("app/assets/tailwind/tokens/_semantic.css")) }
  let(:text_tokens) { %w[on-chrome on-chrome-strong on-chrome-muted on-chrome-hover] }
  let(:mark_tokens) { %w[chrome-mark chrome-focus] }

  # The brand may set one value for both themes; a second occurrence is the dark one.
  def chrome_rgb(css, name, theme)
    found = token_values(css, name)
    return nil if found.empty?

    oklch_to_rgb(*(theme == :dark ? found.fetch(1, found.first) : found.first))
  end

  def violations(css)
    return [] if token_values(css, "chrome").empty?

    %i[light dark].flat_map do |theme|
      chrome = chrome_rgb(css, "chrome", theme)
      (text_tokens + mark_tokens).filter_map do |name|
        color = chrome_rgb(css, name, theme)
        next "--color-#{name} is not set; a branded chrome needs the whole family" unless color

        floor = text_tokens.include?(name) ? ContrastMath::AAA_TEXT_FLOOR : ContrastMath::NON_TEXT_FLOOR
        ratio = contrast_ratio(color, chrome)
        "#{theme} --color-#{name} is #{ratio}:1 on --color-chrome, under #{floor}:1" if ratio < floor
      end
    end.uniq
  end

  it "catches a chrome whose text sinks into it" do
    css = ":root { --color-chrome: oklch(27.1% 0.080 251.6); " \
          "--color-on-chrome: oklch(35% 0.080 251.6); }"

    expect(violations(css)).to include(a_string_matching(/light --color-on-chrome is .* under 7.0:1/))
    expect(violations(css)).to include(a_string_matching(/--color-chrome-focus is not set/))
  end

  it "holds whatever chrome the brand file sets to AAA text and 3:1 marks" do
    expect(violations(brand)).to be_empty, violations(brand).join("\n")
  end

  it "defaults every chrome token to a semantic token the suite already measures" do
    {
      "chrome" => "surface-raised", "chrome-border" => "border",
      "on-chrome" => "text-body", "on-chrome-strong" => "text-heading",
      "on-chrome-muted" => "text-muted", "on-chrome-hover" => "interactive-hover",
      "chrome-mark" => "on-chrome-strong", "chrome-focus" => "interactive-focus"
    }.each do |chrome, base|
      expect(semantic).to match(/--color-#{chrome}:\s*var\(--color-#{base}\);/),
        "--color-#{chrome} should default to var(--color-#{base}) so an unbranded header is today's"
    end
  end
end
