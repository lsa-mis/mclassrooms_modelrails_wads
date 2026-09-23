# frozen_string_literal: true

module UI
  # A static, read-only star rating — fills `value` of `max` stars to display a score (an average review, a satisfaction tally).
  # Usage, options and the accessibility contract: docs/components/rating.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class RatingComponent < ApplicationComponent
    STAR_PATH = "M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"

    # value: the score to display (clamped to 0..max)
    # max:   total stars (default 5)
    def initialize(value: 0, max: 5, **html_attrs)
      @value = value.to_f.clamp(0, max)
      @max = max
      @filled_count = @value.round
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, **root_attrs) { stars }
    end

    private

    def root_attrs
      # Component wins on its a11y contract: merge caller html_attrs FIRST, then
      # apply role/aria-label as overrides so a caller can't clobber the graphic's
      # role or accessible name. Keys are stringified so the overrides land on the
      # same key whether the caller passed `role:` / `"role"` (and likewise aria).
      attrs = { "class" => cn("inline-flex gap-0.5", @extra_class) }
      @html_attrs.each { |k, v| attrs[k.to_s] = v }
      attrs["role"] = "img"
      attrs["aria-label"] = aria_label
      attrs
    end

    def aria_label
      # Trim a whole-number value so "3.0 out of 5 stars" reads "3 out of 5 stars".
      display = (@value % 1).zero? ? @value.to_i : @value
      I18n.t("modelrails_ui.rating.label",
        default: "%{value} out of %{max} stars",
        value: display,
        max: @max)
    end

    def stars
      safe_join(@max.times.map { |i| star(i + 1 <= @filled_count) })
    end

    def star(filled)
      content_tag(:svg,
        content_tag(:path, nil, d: STAR_PATH, "stroke-linecap": "round", "stroke-linejoin": "round"),
        # Filled stars use the semantic warning-icon token (was raw text-yellow-400);
        # the unfilled outline uses the muted body token.
        class: filled ? "size-5 text-warning-icon" : "size-5 text-text-muted",
        xmlns: "http://www.w3.org/2000/svg",
        viewBox: "0 0 24 24",
        fill: filled ? "currentColor" : "none",
        stroke: "currentColor",
        "stroke-width": "2",
        "aria-hidden": "true")
    end
  end
end
