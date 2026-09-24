# frozen_string_literal: true

module UI
  # A styled native `input[type="range"]` slider over the standard min/max/step/value attributes, with AAA accent and focus-ring tokens.
  # Usage, options and the accessibility contract: docs/components/range.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class RangeComponent < ApplicationComponent
    # 2.5.5: the INTERACTION box is 44px tall (h-11) so the whole control is a
    # 44px pointer target — but transparent, so the VISIBLE track stays slim.
    # A slim track painted via ::-slider-runnable-track / ::-moz-range-track
    # keeps the design (a naive `h-11 bg-surface-sunken` made the track a fat
    # 44px pill — 2026-07-13 review). The thumb is 20px (up from 16) for a
    # more grabbable handle, centered on the slim track (webkit `-mt-1.5` =
    # -(20-8)/2 offsets the thumb onto the 8px runnable-track).
    #
    # The track carries the invalid state, and carries it as a BORDER: the ring
    # this replaces was not painted in forced-colors mode, and a colour swap
    # would not survive it either, since the system repaints every border the
    # same. The control's own box is transparent, so the edge has to go on the
    # track pseudo-element rather than the input (modelrails_ui #258).
    BASE = "w-full h-11 cursor-pointer appearance-none bg-transparent outline-none " \
           "focus-ring rounded " \
           "disabled:pointer-events-none disabled:opacity-50 " \
           "[&::-webkit-slider-runnable-track]:h-2 [&::-webkit-slider-runnable-track]:rounded-full [&::-webkit-slider-runnable-track]:bg-surface-sunken " \
           "[&::-moz-range-track]:h-2 [&::-moz-range-track]:rounded-full [&::-moz-range-track]:bg-surface-sunken " \
           "aria-invalid:[&::-webkit-slider-runnable-track]:border-2 aria-invalid:[&::-webkit-slider-runnable-track]:border-danger " \
           "aria-invalid:[&::-moz-range-track]:border-2 aria-invalid:[&::-moz-range-track]:border-danger " \
           "[&::-webkit-slider-thumb]:size-5 [&::-webkit-slider-thumb]:-mt-1.5 [&::-webkit-slider-thumb]:appearance-none " \
           "[&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-interactive " \
           "[&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-surface-raised " \
           "[&::-webkit-slider-thumb]:shadow-xs [&::-webkit-slider-thumb]:transition-[color,box-shadow] " \
           "[&::-moz-range-thumb]:size-5 [&::-moz-range-thumb]:appearance-none " \
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
