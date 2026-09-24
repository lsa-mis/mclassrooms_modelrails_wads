# frozen_string_literal: true

module UI
  # A star rating input — a labelled `role="group"` of star `<button>`s plus a hidden input that carries the chosen value inside a form.
  # Usage, options and the accessibility contract: docs/components/rating_input.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class RatingInputComponent < ApplicationComponent
    STAR_PATH = "M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"

    # value: current rating (integer, clamped to 0..max)
    # max:   total stars (default 5)
    # label: group accessible name (defaults to the i18n "Rating")
    # name:  hidden input name for use inside a <form>
    # url:   endpoint for direct AJAX submission on click
    def initialize(value: 0, max: 5, label: nil, name: nil, url: nil, **html_attrs)
      @value = value.to_i.clamp(0, max)
      @max = max
      @label = label
      @name = name
      @url = url
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, **group_attrs) do
        concat stars
        concat hidden_input if @name
      end
    end

    private

    def group_attrs
      # Component wins on its a11y contract: merge caller html_attrs FIRST, then
      # apply role/aria-label as overrides so a caller can't clobber the group's
      # role or accessible name. Keys are stringified so the overrides land on the
      # same key whether the caller passed `role:` / `"role"` (and likewise aria).
      attrs = { "class" => cn("inline-flex items-center gap-0.5", @extra_class), "data" => controller_data }
      @html_attrs.each { |k, v| attrs[k.to_s] = v }
      attrs["role"] = "group"
      attrs["aria-label"] = group_label
      attrs
    end

    def group_label
      @label.presence || I18n.t("modelrails_ui.rating_input.label", default: "Rating")
    end

    def controller_data
      data = { controller: "rating", rating_value_value: @value }
      data[:rating_url_value] = @url if @url
      data
    end

    def stars
      safe_join(@max.times.map { |i| star_button(i + 1) })
    end

    def star_button(index)
      filled = index <= @value
      content_tag(:button,
        star_svg(filled),
        type: "button",
        # The button is a >=44px hit target (AAA 2.5.5) via min-h-input/min-w-11 +
        # centering; the 24px svg stays the visual size. Filled stars use the
        # semantic warning-icon token (was raw text-yellow-400) — stars are
        # GRAPHIC icons (WCAG 1.4.11 → 3:1, not 7:1 text), and the AAA-tuned
        # amber warning token clears 3:1; the app 0b axe spec verifies the
        # graphic contrast in a real browser.
        class: cn(
          "min-h-input min-w-11 inline-flex items-center justify-center",
          "transition-colors focus-ring rounded-sm",
          filled ? "text-warning-icon" : "text-text-muted"
        ),
        data: {
          rating_target: "star",
          action: "mouseenter->rating#preview mouseleave->rating#resetPreview click->rating#select",
          rating_index_param: index
        },
        "aria-label": I18n.t("modelrails_ui.rating_input.star", default: "Rate %{index} of %{max}", index: index, max: @max))
    end

    def star_svg(filled)
      content_tag(:svg,
        content_tag(:path, nil, d: STAR_PATH, "stroke-linecap": "round", "stroke-linejoin": "round"),
        class: "size-6 pointer-events-none",
        xmlns: "http://www.w3.org/2000/svg",
        viewBox: "0 0 24 24",
        fill: filled ? "currentColor" : "none",
        stroke: "currentColor",
        "stroke-width": "2",
        "aria-hidden": "true")
    end

    def hidden_input
      content_tag(:input, nil,
        type: "hidden",
        name: @name,
        value: @value,
        data: { rating_target: "input" })
    end
  end
end
