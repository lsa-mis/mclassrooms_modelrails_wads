# frozen_string_literal: true

module UI
  # # DataTable
  #
  # A sortable, filterable table with client-side search and pagination. The
  # markup is the static scaffold; all interaction (filter / sort / paginate)
  # lives in the `data-table` Stimulus controller that ships alongside.
  #
  # ## Use when
  # - You have a bounded, already-loaded set of rows the user benefits from
  #   searching, sorting, or paging through entirely on the client.
  #
  # ## Don't use when
  # - The dataset is large or server-paginated — client-side filtering only sees
  #   the rows already in the DOM. Render a server-driven table instead.
  # - The "table" is really a layout grid — use semantic layout, not <table>.
  #
  # ## Accessibility contract
  # - **Guarantees:** sortable columns are real keyboard-operable `<button>`s
  #   (Enter/Space activate; the bare `<th>` is not focusable), each wrapped in a
  #   `th[aria-sort]` the controller flips to `ascending`/`descending`/`none`;
  #   a visually-hidden `role="status"` live region announces the result count
  #   after filtering; all controls (search, sort headers, pager) meet the AAA
  #   44px target floor; and every user-facing string is localized.
  # - **You supply:** a `caption:` — a table without an accessible name leaves
  #   screen-reader users without context. Pass one whenever practical.
  #
  # No fail-loud variant guard: this component has no enum/variant axis. Its
  # inputs are open-ended data (`columns:`, `rows:`, `per_page:`), not a closed
  # set to validate against, so there is nothing to coerce.
  class DataTableComponent < ApplicationComponent
    WRAPPER    = "w-full overflow-auto rounded-lg border border-border"
    TOOLBAR    = "flex items-center gap-3 border-b border-border bg-surface-raised px-4 py-3"
    # h-11 keeps the search control at the AAA 44px target floor (WCAG 2.5.5).
    SEARCH_CLS = "flex h-11 flex-1 items-center gap-2 rounded-md border border-border-strong bg-surface-raised " \
                 "px-3 text-sm text-text-muted focus-within:border-border-focus focus-within:ring-[3px] " \
                 "focus-within:ring-interactive-focus transition"
    SEARCH_INPUT = "w-full bg-transparent outline-none placeholder:text-text-muted text-text-heading text-sm"
    TABLE_CLS  = "w-full caption-bottom text-sm"
    THEAD_CLS  = "bg-surface-sunken/40"
    # h-11 keeps the header row (and therefore the sort buttons that fill it) at
    # the AAA 44px target floor.
    TH_CLS     = "h-11 px-4 text-left align-middle font-medium text-text-muted whitespace-nowrap"
    # The sort trigger is a real <button>: focusable + Enter/Space-activatable
    # for free. It spans the cell (left-aligned) and fills the >=44px height.
    SORT_BTN   = "flex min-h-11 w-full items-center gap-1 -mx-4 px-4 text-left font-medium " \
                 "cursor-pointer select-none hover:text-text-heading focus-visible:outline-none " \
                 "focus-visible:ring-[3px] focus-visible:ring-interactive-focus transition-colors"
    TR_CLS     = "border-t border-border transition-colors hover:bg-surface-sunken/30"
    TD_CLS     = "px-4 py-3 align-middle"
    FOOTER_CLS = "flex items-center justify-between border-t border-border bg-surface-raised px-4 py-3 " \
                 "text-sm text-text-muted"
    # h-11 w-11 keeps the pager buttons at the AAA 44px target floor.
    PAGE_BTN   = "inline-flex h-11 w-11 items-center justify-center rounded-md border border-border " \
                 "hover:bg-surface-sunken hover:text-text-heading disabled:pointer-events-none " \
                 "disabled:opacity-40 focus-visible:outline-none focus-visible:ring-[3px] " \
                 "focus-visible:ring-interactive-focus transition"
    SORT_ASC   = "▲"
    SORT_DESC  = "▼"

    # columns: array of { key:, label:, sortable: true }
    # rows:    array of hashes (keys must match column keys)
    # per_page: rows per page (default 10, 0 = no pagination)
    # caption:  optional <caption> text (strongly encouraged — it is the table's
    #           accessible name)
    def initialize(columns:, rows:, per_page: 10, caption: nil, **html_attrs)
      @columns   = columns
      @rows      = rows
      @per_page  = per_page.to_i
      @caption   = caption
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:div,
        class: cn(WRAPPER, @extra_class),
        data: {
          controller: "data-table",
          data_table_per_page_value: @per_page,
          data_table_total_value: @rows.size,
          # JS-interpolated %{...} templates (the controller does plain %{key}
          # substitution client-side). Localized here so the strings live in the
          # app's locale files, not in the JS.
          data_table_results_template: I18n.t("modelrails_ui.data_table.results", default: "%{count} results"),
          data_table_page_template: I18n.t("modelrails_ui.data_table.page",
            default: "Page %{page} of %{pages} (%{rows} rows)")
        },
        **@html_attrs) do
        concat status_region
        concat toolbar
        concat table_element
        concat footer if @per_page > 0
      end
    end

    private

    # Always-present polite live region. The controller writes the localized
    # result count here after filtering so screen-reader users hear the outcome.
    def status_region
      content_tag(:div, nil,
        role: "status", "aria-live": "polite", class: "sr-only",
        data: { data_table_target: "status" })
    end

    def toolbar
      content_tag(:div, class: TOOLBAR) do
        concat search_box
      end
    end

    def search_box
      content_tag(:label, class: SEARCH_CLS) do
        concat search_icon
        concat tag.input(
          type: "search", class: SEARCH_INPUT,
          # aria-label is the accessible name; the placeholder is only a hint.
          "aria-label": I18n.t("modelrails_ui.data_table.search_label", default: "Search"),
          placeholder: I18n.t("modelrails_ui.data_table.search_placeholder", default: "Search…"),
          data: {
            data_table_target: "search",
            action: "input->data-table#filter"
          })
      end
    end

    def table_element
      content_tag(:table, class: TABLE_CLS) do
        concat content_tag(:caption, @caption, class: "mt-2 text-sm text-text-muted") if @caption
        concat thead
        concat tbody
      end
    end

    def thead
      content_tag(:thead, class: THEAD_CLS) do
        content_tag(:tr) do
          safe_join(@columns.map { |col| th_cell(col) })
        end
      end
    end

    def th_cell(col)
      key      = col[:key].to_s
      label    = col[:label] || key.humanize
      sortable = col.fetch(:sortable, false)

      return content_tag(:th, label, class: TH_CLS) unless sortable

      # Sortable: th[aria-sort] (the controller flips it) wrapping a focusable
      # button that carries the sort action + key param.
      content_tag(:th, sort_button(key, label), class: TH_CLS, "aria-sort": "none")
    end

    def sort_button(key, label)
      content_tag(:button, type: "button", class: SORT_BTN,
        data: { action: "click->data-table#sort", data_table_key_param: key }) do
        concat label
        concat sort_indicator(key, "asc", SORT_ASC)
        concat sort_indicator(key, "desc", SORT_DESC)
      end
    end

    def sort_indicator(key, dir, glyph)
      content_tag(:span, glyph,
        class: "text-xs opacity-0 data-[active=#{dir}]:opacity-100",
        "aria-hidden": "true",
        data: { data_table_target: "sortIndicator", data_table_sort_key: key, data_table_dir: dir })
    end

    def tbody
      content_tag(:tbody, data: { data_table_target: "body" }) do
        safe_join(@rows.map { |row| tr_row(row) })
      end
    end

    def tr_row(row)
      content_tag(:tr, class: TR_CLS, data: { data_table_row: true }) do
        safe_join(@columns.map { |col| td_cell(row, col[:key].to_s) })
      end
    end

    def td_cell(row, key)
      content_tag(:td, row[key.to_sym] || row[key], class: TD_CLS)
    end

    def footer
      content_tag(:div, class: FOOTER_CLS) do
        concat content_tag(:span, "",
          data: { data_table_target: "pageLabel" })
        concat(content_tag(:div, class: "flex items-center gap-1") {
          concat page_btn("‹", "click->data-table#prevPage",
            I18n.t("modelrails_ui.data_table.prev_page", default: "Previous page"))
          concat page_btn("›", "click->data-table#nextPage",
            I18n.t("modelrails_ui.data_table.next_page", default: "Next page"))
        })
      end
    end

    def page_btn(label, action, aria)
      content_tag(:button, label, type: "button",
        class: PAGE_BTN,
        "aria-label": aria,
        data: { action: action })
    end

    def search_icon
      content_tag(:svg,
        safe_join([
          content_tag(:circle, nil, cx: "11", cy: "11", r: "8"),
          content_tag(:path, nil, d: "m21 21-4.3-4.3")
        ]),
        xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24",
        fill: "none", stroke: "currentColor", "stroke-width": "2",
        "stroke-linecap": "round", "stroke-linejoin": "round",
        class: "size-4 shrink-0", "aria-hidden": "true")
    end
  end
end
