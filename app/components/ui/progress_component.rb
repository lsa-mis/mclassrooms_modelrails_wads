# frozen_string_literal: true

module UI
  # # Progress
  #
  # A determinate progress bar — a filled track communicating a known percentage
  # toward completion. For indeterminate waits, use `spinner` instead.
  #
  # ## Use when
  # - You can express progress as a value between 0 and `max` (upload %, steps done).
  #
  # ## Don't use when
  # - The wait is indeterminate — use `spinner`.
  # - The bar has no accessible name and no nearby text — pass `label:` so screen
  #   readers can announce what is progressing.
  #
  # ## Accessibility contract
  # - **Guarantees:** `role="progressbar"` with `aria-valuenow`/`min`/`max`, the
  #   value clamped to 0–100% so a bad value never overflows the track.
  # - **You supply:** `label:` when no visible text names the bar (it becomes the
  #   `aria-label` / accessible name).
  class ProgressComponent < ApplicationComponent
    # Bar-vs-track graphic contrast: bg-interactive fill over a bg-interactive/20
    # track. CI-verify the 3:1 non-text graphic contrast for this pairing.
    TRACK = "relative h-2 w-full overflow-hidden rounded-full bg-interactive/20"
    BAR = "h-full w-full flex-1 bg-interactive transition-all"

    # value: current progress (clamped to 0..max)
    # max:   the value representing 100%
    # label: accessible name for the bar (becomes aria-label) when no visible text names it
    def initialize(value: 0, max: 100, label: nil, **html_attrs)
      @value = value
      @max = max
      @label = label
      @pct = [ [ @value.to_f / @max * 100, 0 ].max, 100 ].min
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      attrs = {
        class: cn(TRACK, @extra_class),
        role: "progressbar",
        "aria-valuenow": @value,
        "aria-valuemin": 0,
        "aria-valuemax": @max
      }
      attrs[:"aria-label"] = @label if @label

      content_tag(:div, **attrs, **@html_attrs) do
        content_tag(:div, nil, class: BAR, style: "width: #{@pct.round(2)}%")
      end
    end
  end
end
