# frozen_string_literal: true

module UI
  # # Calendar
  #
  # An inline single-month date grid. The month is a `role="grid"` named by its
  # month/year caption; each day is a `role="gridcell"` wrapping a real `<button>`
  # whose accessible name is the full date. Paging and roving-tabindex arrow-key
  # navigation (←/→ day, ↑/↓ week, Home/End, PageUp/PageDown) live in the
  # `calendar` Stimulus controller.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named grid; weekday `columnheader`s; day buttons with
  #   full-date accessible names; `aria-selected` on the selected cell,
  #   `aria-current="date"` on today; exactly one day in the tab order (roving
  #   tabindex) with arrow-key navigation; i18n-labelled prev/next buttons; and
  #   the AAA offset `focus-ring` on every control.
  # - **You supply:** `selected:`/`month:` Dates and optional `min:`/`max:` bounds.
  # @logical_path Forms & Inputs
  class CalendarComponentPreview < ViewComponent::Preview
    include UIHelper

    # The default month grid with a selected day. Tab to a day, then use the
    # arrow keys to move focus across the grid.
    def default
    end

    # A range-bounded grid: days before `min:` / after `max:` are disabled.
    def bounded
    end

    # Weeks starting on Monday — the first column is Mo, the last is Su.
    def monday_start
    end
  end
end
