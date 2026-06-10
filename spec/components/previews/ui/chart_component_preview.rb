# frozen_string_literal: true

module UI
  # # Chart
  #
  # A data-visualization wrapper: a `<canvas>` wired to `chart_controller.js` (a
  # thin Chart.js adapter). Chart.js is NOT bundled — pin it in your importmap
  # (`pin "chart.js", to: "https://esm.sh/chart.js@4"`) before use.
  #
  # ## Use when
  # - You're plotting a small set of series (bar/line/pie/…) and can summarize the
  #   chart in one line and supply the underlying numbers.
  #
  # ## Don't use when
  # - You can't describe the data — a `<canvas>` is an opaque bitmap, so without a
  #   `label:` summary and well-formed `datasets:` (each with a `label:`), screen-
  #   reader users get nothing.
  #
  # ## Accessibility contract
  # - **Guarantees:** the canvas is a labelled graphic (`role="img"` + `aria-label`
  #   from `label:`), and a **visually-hidden data `<table>`** (caption + scoped
  #   headers) carries the real numbers, wired via `aria-describedby` — the WAI/APG
  #   complex-image text alternative. Series default to an AAA-tuned OKLCH palette
  #   (never raw hex). An unknown `type:` fails loud.
  # - **You supply:** a meaningful `label:`, `labels:`, and `datasets:` (each named).
  # @logical_path Data Display
  class ChartComponentPreview < ViewComponent::Preview
    include UIHelper

    # A grouped bar chart with two named series — note the labelled graphic and the
    # adjacent (visually-hidden) data table in the rendered HTML.
    def default
    end

    # A line chart. The same a11y scaffolding applies regardless of `type:`.
    def line
    end

    # A pie chart driven by a single series — categories come from `labels:`.
    def pie
    end
  end
end
