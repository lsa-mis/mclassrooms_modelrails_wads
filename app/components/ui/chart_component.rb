# frozen_string_literal: true

module UI
  # # Chart
  #
  # A data-visualization wrapper — renders a `<canvas>` wired to
  # `chart_controller.js` (a thin adapter for Chart.js). The Chart.js library
  # itself is NOT bundled; add it to your importmap before use:
  #
  #   # config/importmap.rb
  #   bin/importmap pin chart.js   (downloads to vendor/javascript — production CSP allows no CDN)
  #
  # ## Usage
  #   ui :chart, type: :bar, label: "Quarterly revenue vs. costs",
  #     labels: ["Jan", "Feb", "Mar"],
  #     datasets: [
  #       { label: "Revenue", data: [100, 200, 150] },
  #       { label: "Costs",   data: [80,  140, 110] }
  #     ]
  #
  # ## Options
  #   type:     :bar | :line | :pie | :doughnut | :radar | :polarArea (default: :bar).
  #             An unknown type FAILS LOUD (raises ArgumentError) — no silent fallback.
  #   label:    a one-line summary of what the chart shows (REQUIRED for AT — see
  #             the accessibility contract). Falls back to an i18n default.
  #   labels:   array of x-axis / category labels
  #   datasets: array of dataset hashes ({ label:, data: [...] }); snake_case keys
  #             are camelized for Chart.js (background_color: → backgroundColor:).
  #             Series with no explicit color are auto-assigned from an AAA-tuned
  #             OKLCH palette (DEFAULT_SERIES) — never a raw hex.
  #   options:  hash merged into Chart.js `options` (e.g. { responsive: false })
  #
  # ## Accessibility contract
  # A `<canvas>` is an opaque bitmap — pixels carry no semantics, so a chart drawn
  # to it is invisible to assistive tech (a WCAG 1.1.1 non-text-content failure).
  # We give AT TWO things, mirroring the WAI/APG "complex image" pattern:
  #
  # - **Guarantees:**
  #   1. The canvas is a labelled graphic: `role="img"` + an `aria-label` summary
  #      (from `label:`, i18n-defaulted) so AT announces *what the chart is*, not an
  #      anonymous canvas. The component owns this — a caller can't clobber it.
  #   2. A **visually-hidden data table** (`.sr-only`) renders the same numbers as
  #      a real `<table>` (caption + `<th scope>` row/column headers), wired to the
  #      canvas via `aria-describedby`. Screen-reader users get the actual data, not
  #      just the summary — the textual equivalent the bitmap can't provide.
  #   - Decorative SVG/canvas chrome is `aria-hidden`; the only AT-visible content
  #     is the label + the table.
  # - **You supply:** a meaningful `label:` and well-formed `datasets:` (each with a
  #   `label:` so the table columns are named). Color is optional — the palette is
  #   AAA-tuned by default; if you override, keep series ≥3:1 against the surface
  #   (WCAG 1.4.11, graphics) and don't rely on color alone to distinguish series.
  class ChartComponent < ApplicationComponent
    TYPES = %w[bar line pie doughnut radar polarArea].freeze

    WRAPPER_CLS = "relative"

    # AAA-tuned OKLCH series palette. Same recipe as the `bg-hue-*` design tokens
    # (L=0.35, C=0.20 — clears 7:1 against white text and ≥3:1 against the page
    # surface) spread across distinct hues. Chart.js draws to a bitmap and can't
    # consume CSS classes, so we hand it concrete OKLCH strings — semantic values,
    # never raw hex. Callers override per-dataset via `background_color:`.
    DEFAULT_SERIES = [
      "oklch(0.35 0.20 264)", # blue
      "oklch(0.35 0.20 150)", # green
      "oklch(0.35 0.20 25)",  # red
      "oklch(0.35 0.20 300)", # purple
      "oklch(0.35 0.20 60)",  # amber
      "oklch(0.35 0.20 200)"  # teal
    ].freeze

    def initialize(type: :bar, label: nil, labels: [], datasets: [], options: {}, **html_attrs)
      unless TYPES.include?(type.to_s)
        raise ArgumentError,
          "Unknown chart type: #{type.inspect}. Allowed: #{TYPES.join(", ")}"
      end

      @type = type.to_s
      @label = label
      @labels = labels
      @datasets = datasets
      @chart_options = options
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
      @table_id = "chart-data-#{object_id}"
    end

    def call
      content_tag(:div, class: cn(WRAPPER_CLS, @extra_class)) do
        safe_join([ canvas_tag, data_table ])
      end
    end

    private

    # The canvas is a single labelled graphic. Caller html_attrs merge FIRST, then
    # the a11y attributes apply as overrides so a caller can't strip role / name /
    # the table description (mirrors the rating component's contract).
    def canvas_tag
      attrs = {}
      @html_attrs.each { |k, v| attrs[k.to_s] = v }
      attrs["data"] = {
        controller: "chart",
        chart_type_value: @type,
        chart_config_value: config_json
      }
      attrs["role"] = "img"
      attrs["aria-label"] = aria_label
      attrs["aria-describedby"] = @table_id
      tag.canvas(**attrs)
    end

    def aria_label
      @label.presence || I18n.t("modelrails_ui.chart.label", default: "Chart")
    end

    # The textual equivalent: a real <table> the bitmap can't be. Visually hidden
    # (.sr-only) but in the a11y tree, referenced by the canvas' aria-describedby.
    def data_table
      content_tag(:table, class: "sr-only", id: @table_id) do
        safe_join([
          content_tag(:caption, aria_label),
          table_head,
          table_body
        ])
      end
    end

    def table_head
      headers = [ content_tag(:th, "", scope: "col") ] +
        @datasets.map { |d| content_tag(:th, d[:label].to_s, scope: "col") }
      content_tag(:thead, content_tag(:tr, safe_join(headers)))
    end

    def table_body
      rows = @labels.each_with_index.map do |label, row|
        cells = [ content_tag(:th, label.to_s, scope: "row") ] +
          @datasets.map { |d| content_tag(:td, Array(d[:data])[row].to_s) }
        content_tag(:tr, safe_join(cells))
      end
      content_tag(:tbody, safe_join(rows))
    end

    def config_json
      ds = @datasets.each_with_index.map do |d, i|
        camelize_keys(with_default_color(d, i)).compact
      end
      { labels: @labels, datasets: ds, options: @chart_options }.to_json
    end

    # Assign an AAA-tuned palette color when the caller didn't specify one, so a
    # chart is never drawn with an off-system raw color by default.
    def with_default_color(dataset, index)
      return dataset if dataset.key?(:background_color) || dataset.key?(:backgroundColor)

      dataset.merge(background_color: DEFAULT_SERIES[index % DEFAULT_SERIES.size])
    end

    def camelize_keys(hash)
      hash.transform_keys { |k| k.to_s.camelize(:lower) }
    end
  end
end
