# frozen_string_literal: true

module UI
  # # Badge
  #
  # A small status/category label — a compact pill that tags surrounding content.
  # Renders a `<span>`, or an `<a>` when `href:` is given (a clickable tag/filter link).
  #
  # ## Use when
  # - A short inline label that classifies or annotates nearby content (status pill,
  #   category tag, small count).
  #
  # ## Don't use when
  # - It's a real action — use `UI::ButtonComponent` (or `button_to` for non-GET).
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA-contrast text on every variant, including the adaptive
  #   signal treatments (`danger`/`success`/`info`/`warning`) that stay legible in dark mode.
  # - **You supply:** an accessible name when the badge conveys status not already in
  #   the surrounding text, and a valid `variant` (an unknown one raises in development).
  #
  # ## Variants
  # Signal levels: `info` · `success` · `warning` · `danger` (tinted chips —
  # soft `*-surface` + saturated `text-<level>`, matching the alert + toast cards).
  # Style levels: `default` · `secondary` · `outline` · `ghost` · `link`.
  # (`destructive` is a non-breaking alias for `danger`.)
  class BadgeComponentPreview < ViewComponent::Preview
    include UIHelper

    # The default, high-emphasis label.
    def default
    end

    # Neutral / lower-emphasis label.
    def secondary
    end

    # Informational signal — tinted info chip.
    def info
    end

    # Success / completed status — tinted success chip.
    def success
    end

    # Warning status — tinted warning chip (soft amber surface + dark amber text).
    def warning
    end

    # Error / removed / failed status — tinted danger chip; keeps a danger focus ring.
    def danger
    end

    # `variant: :destructive` is a non-breaking alias for `:danger`.
    def destructive
    end

    # Outlined label — a border with no fill.
    def outline
    end

    # Minimal label — no fill, no border; reveals a surface tint on hover when linked.
    def ghost
    end

    # Link-styled label — pair with `href:` for a clickable tag/filter.
    def link
    end

    # Linked badge: pass `href:` and the component renders an `<a>`.
    def link_href
    end

    # Edit `label` and `variant` live to explore the component.
    # @param label text
    # @param variant select [default, secondary, info, success, warning, danger, destructive, outline, ghost, link]
    def playground(label: "Badge", variant: :default)
      ui :badge, label, variant: variant.to_sym
    end

    # ## Don't — a badge as an action
    #
    # A badge is presentational. Don't wire a click handler onto a bare badge to fake
    # a button — screen-reader and keyboard users get no interactive affordance.
    # Use `UI::ButtonComponent` for actions, or pass `href:` for genuine navigation.
    # @label Don't · badge as an action
    def dont_action
    end
  end
end
