# frozen_string_literal: true

module UI
  # A server-rendered data table: caption, toolbar, header, body and footer slots around a plain <table>; sorting, filtering and paging are the caller's (a GET form, pagy).
  # Usage, options and the accessibility contract: docs/components/table.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class TableComponent < ApplicationComponent
    # `bg-surface` is the list_group's card colour, deliberately: a table and a
    # list group sitting side by side should read as the same kind of container.
    # The gem's card surfaces disagree today (card is bg-surface-raised,
    # data_table is transparent) — that inconsistency is tracked separately, and
    # this component follows the list rather than adding a fourth answer.
    WRAPPER = "rounded-lg border border-border bg-surface-raised overflow-hidden"
    TABLE   = "w-full text-sm"
    THEAD   = "bg-surface-sunken/40"
    # h-11 keeps a header row (and any sort link filling it) at the AAA 44px target floor.
    TH      = "h-11 px-4 text-left align-middle text-sm font-medium text-text-muted whitespace-nowrap"
    # No border-t: a pagination partial placed here draws its own.
    FOOTER  = "text-sm text-text-muted"
    # The card's own top band — a summary, a filters-applied state, a Clear link —
    # so the table's context sits inside the border instead of floating above it.
    TOOLBAR = "flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3"
    SIZES   = { default: "default", compact: "compact" }.freeze

    renders_one :toolbar
    renders_one :header
    renders_one :body
    renders_one :footer

    # caption:         the table's accessible name (REQUIRED — a nameless table is
    #                  the defect this component exists to prevent, so a blank one raises)
    # caption_visible: render the caption as visible text rather than sr-only
    # size:            :default | :compact — exposed as data-size for row partials
    # scroll:          nil | :horizontal — wraps ONLY the <table> in a named, focusable
    #                  scroll region (the ScrollArea contract), so a wide table scrolls
    #                  under a toolbar and footer that stay put. Wrapping the whole
    #                  component instead carries the toolbar's controls and the footer's
    #                  pager off-screen with the columns at phone width.
    def initialize(caption:, caption_visible: false, size: :default, scroll: nil, **html_attrs)
      raise ArgumentError, "UI::TableComponent needs a caption — it is the table's accessible name" if caption.nil? || caption.to_s.strip.empty?
      raise ArgumentError, "UI::TableComponent size: must be one of #{SIZES.keys.inspect}" unless SIZES.key?(size.to_sym)
      raise ArgumentError, "UI::TableComponent scroll: must be nil or :horizontal" unless scroll.nil? || scroll.to_sym == :horizontal

      @caption = caption
      @caption_visible = caption_visible
      @size = size.to_sym
      @scroll = scroll&.to_sym
      @extra_class = html_attrs.delete(:class)
      # Merge the size attribute into any caller `data:` so a passed-through
      # `data:` attr can't clobber `data-size` and silently break row partials
      # that key off it.
      @data = { size: SIZES[@size] }.merge(html_attrs.delete(:data) || {})
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, class: cn(WRAPPER, @extra_class), data: @data, **@html_attrs) do
        concat content_tag(:div, toolbar, class: TOOLBAR, data: { slot: "toolbar" }) if toolbar?
        concat(@scroll ? scroll_region { table } : table)
        concat content_tag(:div, footer, class: FOOTER, data: { slot: "footer" }) if footer?
      end
    end

    private

    # Named distinctly from the caption: an identical name makes a screen reader
    # announce the same words twice, once for the region and once for the table.
    def scroll_region(&)
      render(UI::ScrollAreaComponent.new(orientation: @scroll, max_h: nil,
        aria_label: I18n.t("modelrails_ui.table.scroll_region", name: @caption,
          default: "%{name}, scrolls sideways")), &)
    end

    def table
      content_tag(:table, class: TABLE) do
        concat content_tag(:caption, @caption, class: (@caption_visible ? CAPTION_VISIBLE : "sr-only"))
        concat content_tag(:thead, content_tag(:tr, header), class: THEAD) if header?
        concat content_tag(:tbody, body) if body?
      end
    end

    CAPTION_VISIBLE = "px-4 py-2 text-left text-sm text-text-muted"
  end
end
