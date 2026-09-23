# frozen_string_literal: true

# WCAG contrast, computed from the design tokens as they ship.
#
# This exists because **axe measures TEXT contrast only** — it has no non-text
# rule — so nothing in the accessibility gate can tell whether an icon, a
# border or any other graphic object is visible against the surface it sits on.
# That blind spot let the signal chip borders sit under the floor until someone
# measured them by hand (modelrails_ui#257) and let a success toast ship at
# 1.32:1 (#1236). Both fixes needed the same arithmetic, so it lives here once
# rather than in each spec — two copies of a colour-space conversion is exactly
# the drift these guards exist to prevent.
module ContrastMath
  # WCAG 2.x thresholds. AAA text is 7:1; a graphic object or UI component
  # boundary answers to 1.4.11's 3:1 instead.
  NON_TEXT_FLOOR = 3.0
  AAA_TEXT_FLOOR = 7.0

  module_function

  # An `oklch(L% C H)` triple -> linear sRGB in 0..1.
  #
  # Clamped, not gamut-mapped: a token outside sRGB would be clipped by the
  # browser too, so clipping here measures what a screen actually shows.
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

  # Composite a translucent colour over its backdrop. A token carrying an alpha
  # must be measured as composited — reading the raw value flatters it, which
  # is how the toast pill's icon looked fine on paper.
  def composite(foreground, alpha, backdrop)
    foreground.each_with_index.map { |v, i| (v * alpha) + (backdrop[i] * (1 - alpha)) }
  end

  # Every `--color-<name>: oklch(...)` in a stylesheet, in source order. The
  # app writes its light theme first and its dark theme second, so index 0 is
  # light and index 1 is dark — asserted by the callers' own controls rather
  # than assumed here.
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
