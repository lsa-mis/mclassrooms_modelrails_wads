# frozen_string_literal: true

module UI
  # # Range
  #
  # A styled native `input[type="range"]` slider over min/max/step/value, with AAA
  # accent and focus-ring tokens. A native slider carries no visible label, so you
  # supply one externally (an `id` is always emitted so the `<label for>` can target
  # it), and on error `invalid: true` + `describedby:`.
  #
  # ## Use when
  # - The user picks a value from a continuous, bounded numeric range and an
  #   approximate position is acceptable (volume, brightness, zoom).
  #
  # ## Don't use when
  # - An exact value matters or the range is unbounded — use a number input.
  # - The choice is a small set of discrete options — use a select or radio_group.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA accent/focus-ring tokens, an `id` ALWAYS emitted on the
  #   `<input>`, `aria-invalid="true"` when `invalid: true`, and `aria-describedby`
  #   wired when `describedby:` is supplied. The thumb target size is UA-controlled
  #   (native range), so the app's axe gate is the AAA target-size authority here.
  # - **You supply:** the visible label as an EXTERNAL `<label for="<id>">` — unlike
  #   checkbox, this component does NOT bundle a label. On error, pass `invalid: true`
  #   and point `describedby:` at the error element's id.
  #
  # ## Optional value readout
  # Pass `show_value: true` to render an associated `<output>` (an implicit
  # `role="status"` live region) that mirrors the slider, kept in sync by the
  # `range` Stimulus controller. The default stays a bare native slider.
  class RangeComponentPreview < ViewComponent::Preview
    include UIHelper

    # A native slider with a sibling label — the baseline appearance.
    def default
    end

    # `value:` PRE-POSITIONS the thumb only — it does NOT display the number.
    # For a visible readout use `show_value: true` (see with_value_display).
    def initial_value
    end

    # `show_value: true` renders an associated `<output>` readout that mirrors the
    # slider live (synced by the `range` controller). Drag the thumb to see it update.
    def with_value_display
    end

    # Error state: `aria-invalid="true"` plus `aria-describedby` wired to a sibling
    # error message. In a real form the form builder sets both automatically.
    def invalid
    end

    # Disabled control — passed straight through via `**html_attrs`.
    def disabled
    end
  end
end
