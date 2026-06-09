# frozen_string_literal: true

module UI
  # # Range
  #
  # A styled native `input[type="range"]` slider over the standard min/max/step/value
  # attributes, with AAA accent and focus-ring tokens. The slider has no built-in
  # visible label, so you supply one externally (an `id` is always emitted so the
  # `<label for>` can target it), and on error `invalid: true` + `describedby:`.
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
  # - **You supply:** the visible label as an EXTERNAL `<label for="<id>">` — a native
  #   slider is conventionally labeled by a separate form label. On error, pass
  #   `invalid: true` and point `describedby:` at the error element's id.
  #
  # ## Optional value readout (`show_value: true`)
  # By default this renders a bare native slider. Pass `show_value: true` to also
  # render an associated `<output for="<id>">` that mirrors the current value. The
  # `<output>` is an implicit `role="status"` live region, kept in sync with the
  # slider by the tiny `range` Stimulus controller (`range_controller.js`): the
  # input carries `data-action="input->range#sync"` and both elements are
  # `data-range-target`s. The SSR text starts at `value:` (or the native midpoint
  # when `value:` is nil) and the controller resyncs on connect.
  #
  # No fail-loud guard — there's no enum axis to validate.
  class RangeComponent < ApplicationComponent
    BASE = "w-full cursor-pointer appearance-none rounded-full bg-surface-sunken outline-none " \
           "h-2 accent-interactive " \
           "focus-ring " \
           "aria-invalid:ring-danger " \
           "disabled:pointer-events-none disabled:opacity-50 " \
           "[&::-webkit-slider-thumb]:size-4 [&::-webkit-slider-thumb]:appearance-none " \
           "[&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-interactive " \
           "[&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-surface-raised " \
           "[&::-webkit-slider-thumb]:shadow-xs [&::-webkit-slider-thumb]:transition-[color,box-shadow] " \
           "[&::-moz-range-thumb]:size-4 [&::-moz-range-thumb]:appearance-none " \
           "[&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:bg-interactive " \
           "[&::-moz-range-thumb]:border-2 [&::-moz-range-thumb]:border-surface-raised " \
           "[&::-moz-range-thumb]:border-solid [&::-moz-range-thumb]:shadow-xs"

    # min / max / step / value: native range attributes
    #   invalid:     sets `aria-invalid="true"` (absent when false)
    #   describedby: sets `aria-describedby` (link to the error/hint element id)
    #   show_value:  also renders an associated `<output>` readout synced by the
    #                `range` Stimulus controller (default false = bare slider)
    def initialize(min: 0, max: 100, step: 1, value: nil, invalid: false, describedby: nil,
                   show_value: false, **html_attrs)
      @min   = min
      @max   = max
      @step  = step
      @value = value
      @invalid = invalid
      @describedby = describedby
      @show_value = show_value
      # External-label association: an id is ALWAYS emitted so a sibling
      # `<label for>` can target this control. Prefer an explicit id, fall back to a
      # sanitized name, then a stable per-instance id.
      @id = html_attrs[:id] || html_attrs[:name]&.gsub(/\W/, "_") || "range_#{object_id}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      # Default: a bare native slider (output byte-identical to the pre-readout
      # component). With `show_value:` the slider is wrapped beside an `<output>`
      # readout that the `range` controller keeps in sync.
      return content_tag(:input, nil, **range_attrs) unless @show_value

      content_tag(:div, class: "flex items-center gap-3", data: { controller: "range" }) do
        safe_join([
          content_tag(:input, nil, **range_attrs.merge(
            data: { "range-target" => "input", action: "input->range#sync" }
          )),
          content_tag(:output, output_text,
            for: @id,
            class: "text-sm tabular-nums text-text-body min-w-[3ch] text-right",
            data: { "range-target" => "output" })
        ])
      end
    end

    private

    def range_attrs
      attrs = @html_attrs.merge(
        type: "range",
        min: @min,
        max: @max,
        step: @step,
        id: @id,
        class: cn(BASE, @extra_class)
      )
      attrs[:value] = @value unless @value.nil?
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      attrs
    end

    # Initial SSR readout text: the supplied value, or the native midpoint when
    # nil so the server-rendered text matches the slider's default thumb position.
    # The `range` controller resyncs on connect either way.
    def output_text
      @value.nil? ? ((@min + @max) / 2) : @value
    end
  end
end
