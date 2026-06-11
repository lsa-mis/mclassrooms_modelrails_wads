# frozen_string_literal: true

module UI
  # # DataTable
  #
  # A sortable, filterable table with client-side search and pagination. Sortable
  # columns are keyboard-operable `<button>`s inside `th[aria-sort]`; a visually-hidden
  # live region announces the result count after filtering. Behavior lives in the
  # `data-table` Stimulus controller that ships alongside this component.
  #
  # ## Use when
  # - You have a bounded, already-loaded set of rows worth searching, sorting, or
  #   paging through entirely on the client.
  #
  # ## Don't use when
  # - The dataset is large or server-paginated — client-side filtering only sees the
  #   rows already in the DOM; render a server-driven table instead.
  #
  # ## Accessibility contract
  # - **Guarantees:** keyboard-operable sort headers with `aria-sort` flipped by the
  #   controller, a polite live-region result-count announcement on filter, AAA 44px
  #   targets on every control, and fully localized strings.
  # - **You supply:** a `caption:` — the table's accessible name. Pass one whenever
  #   practical so screen-reader users get context.
  # @logical_path Data Display
  class DataTableComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # A few sortable + one non-sortable column, rows, and a caption (the
    # accessible name). Try Tab-ing to a header and pressing Enter to sort.
    def default
    end

    # Small `per_page` so the pager renders. The footer shows the localized
    # "Page X of Y (N rows)" label; filtering announces "N results".
    def paginated
    end

    # No `sortable: true` on any column — plain `<th>`s, no sort buttons, no
    # `aria-sort`. Search still works.
    def not_sortable
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — a table with no caption
    #
    # A `<table>` with no `caption:` (and no other accessible name) leaves
    # screen-reader users without context for what the data represents. Always
    # pass a descriptive `caption:`.
    # @label Don't · no caption (no accessible name)
    def dont_no_caption
    end

    # @!endgroup
  end
end
