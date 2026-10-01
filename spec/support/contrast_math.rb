# frozen_string_literal: true

# WCAG contrast computed from the shipped tokens, because axe measures text only
# (modelrails_ui#257, #1236).
module ContrastMath
  # AAA text is 7:1; a graphic object or component boundary is 3:1 (WCAG 1.4.11).
  NON_TEXT_FLOOR = 3.0
  AAA_TEXT_FLOOR = 7.0

  module_function

  # oklch -> linear sRGB, clamped as the browser clips it.
  def oklch_to_rgb(lightness_percent, chroma, hue_degrees)
    l = lightness_percent / 100.0
    rad = hue_degrees * Math::PI / 180
    a = chroma * Math.cos(rad)
    b = chroma * Math.sin(rad)

    lms = [ l + (0.3963377774 * a) + (0.2158037573 * b),
            l - (0.1055613458 * a) - (0.0638541728 * b),
            l - (0.0894841775 * a) - (1.2914855480 * b) ].map { |v| v**3 }

    [ (4.0767416621 * lms[0]) - (3.3077115913 * lms[1]) + (0.2309699292 * lms[2]),
      (-1.2684380046 * lms[0]) + (2.6097574011 * lms[1]) - (0.3413193965 * lms[2]),
      (-0.0041960863 * lms[0]) - (0.7034186147 * lms[1]) + (1.7076147010 * lms[2]) ]
      .map { |v| v.clamp(0.0, 1.0) }
  end

  def relative_luminance(rgb)
    r, g, b = rgb
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  def contrast_ratio(foreground, background)
    a = relative_luminance(foreground)
    b = relative_luminance(background)
    (([ a, b ].max + 0.05) / ([ a, b ].min + 0.05)).round(2)
  end

  # A translucent token is measured composited; its raw value flatters it.
  def composite(foreground, alpha, backdrop)
    foreground.each_with_index.map { |v, i| (v * alpha) + (backdrop[i] * (1 - alpha)) }
  end

  # Every --color-<name>: oklch(...) in source order: light first, then dark.
  def token_values(css, name)
    css.scan(/--color-#{Regexp.escape(name)}:\s*oklch\(\s*([\d.]+)%\s+([\d.]+)\s+([\d.]+)/)
       .map { |triple| triple.map(&:to_f) }
  end

  def token(css, name, theme)
    found = token_values(css, name)
    raise ArgumentError, "no --color-#{name} found in that stylesheet" if found.empty?

    found.fetch(theme == :light ? 0 : 1)
  end

  def token_rgb(css, name, theme)
    oklch_to_rgb(*token(css, name, theme))
  end
end
