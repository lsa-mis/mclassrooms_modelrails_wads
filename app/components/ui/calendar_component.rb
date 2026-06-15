# frozen_string_literal: true

module UI
  # # Calendar
  #
  # A single-month date grid: a prev/next month header over a 6×7 grid of day
  # buttons. Selected/today dates are highlighted; `min`/`max` disable days
  # outside the range. The month label and grid contents are kept in sync by the
  # `calendar` Stimulus controller (prev/next paging + roving-tabindex arrow-key
  # navigation across the grid).
  #
  # ## Use when
  # - You need an inline month picker the user navigates by mouse OR keyboard.
  #
  # ## Don't use when
  # - You only need a native date field — use `<input type="date">` (the OS picker
  #   is already accessible and localized).
  #
  # ## Accessibility contract
  # - **Guarantees:** the month is a `role="grid"` with an accessible name (the
  #   month/year caption); the weekday header is a `role="row"` of
  #   `role="columnheader"` cells; each day is a `role="gridcell"` wrapping a real
  #   `<button>` whose accessible name is the full localized date ("15 June 2026");
  #   the selected day carries `aria-selected="true"`, today carries
  #   `aria-current="date"`; exactly one day is in the tab order (roving tabindex)
  #   and the controller moves focus with ←/→ (day), ↑/↓ (week), Home/End (row
  #   ends), PageUp/PageDown (month); prev/next are i18n-labelled `<button>`s (not
  #   icon-only-unlabelled); and every control carries the AAA offset `focus-ring`.
  # - **You supply:** `selected:`/`month:` Dates and optional `min:`/`max:` bounds.
  #
  # selected:       Date or nil — highlighted day
  # month:          Date — controls which month is shown (defaults to today)
  # name:           form field name for the hidden input (if used in a form)
  # min/max:        Date bounds for disabled days
  # weekday_start:  :sunday (default) or :monday — first column of the grid

  class CalendarComponent < ApplicationComponent
    CONTAINER  = "w-fit rounded-lg border border-border bg-surface-overlay p-4 text-sm shadow"
    HEADER_CLS = "mb-3 flex items-center justify-between"
    MONTH_CLS  = "font-medium text-text-heading"
    # 44px AAA target; the offset outline (focus-ring) survives overflow:hidden
    # ancestors and forced-colors mode, where a box-shadow ring is clipped.
    NAV_BTN    = "inline-flex size-11 items-center justify-center rounded-md focus-ring " \
                 "text-text-muted hover:bg-surface-sunken hover:text-text-heading transition"
    GRID_CLS   = "grid grid-cols-7 gap-px"
    ROW_CLS    = "contents"
    DOW_CLS    = "py-1.5 text-center text-xs text-text-muted font-medium"
    CELL_CLS   = "contents"
    DAY_BASE   = "h-11 w-11 rounded-md text-center text-sm transition-colors focus-ring"
    DAY_NORMAL = "hover:bg-surface-sunken hover:text-text-heading"
    DAY_TODAY  = "font-semibold ring-1 ring-border"
    DAY_SEL    = "bg-interactive text-text-on-interactive hover:bg-interactive-hover"
    DAY_MUTED  = "text-text-muted"
    DAY_DISABLED = "pointer-events-none opacity-30"

    CHEVRON_L = "m15 18-6-6 6-6"
    CHEVRON_R = "m9 18 6-6-6-6"

    # Weekday columns keyed by where the week begins. The `:title` is the full
    # localized day name (the `<abbr>`'s accessible expansion); `:abbr` is the
    # visible two-letter label. Index follows Date#wday (0 = Sunday).
    WEEKDAY_STARTS = { sunday: 0, monday: 1 }.freeze

    def initialize(selected: nil, month: nil, name: nil, min: nil, max: nil,
                   weekday_start: :sunday, **html_attrs)
      @selected = selected
      @month    = (month || Date.today).beginning_of_month
      @name     = name
      @min      = min
      @max      = max

      # Fail loud: an unknown weekday_start would silently mis-order the columns
      # (a correctness bug a caller can't see), so reject it rather than coerce.
      @week_offset = WEEKDAY_STARTS.fetch(weekday_start) do
        raise ArgumentError,
          "UI::CalendarComponent: unknown weekday_start #{weekday_start.inspect} " \
          "(allowed: #{WEEKDAY_STARTS.keys.map(&:inspect).join(', ')})"
      end

      @extra_class = html_attrs.delete(:class)
      # Merge our controller wiring with any caller-supplied `data:` so a passed
      # `data:` hash doesn't clobber `data-controller`/`calendar_month_value`.
      @html_data  = html_attrs.delete(:data) || {}
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div,
        class: cn(CONTAINER, @extra_class),
        data: { controller: "calendar", calendar_month_value: @month.iso8601 }.merge(@html_data),
        **@html_attrs) do
        concat hidden_input if @name && @selected
        concat header_row
        concat month_grid
      end
    end

    private

    def hidden_input
      tag.input(type: "hidden", name: @name, value: @selected&.iso8601)
    end

    def header_row
      content_tag(:div, class: HEADER_CLS) do
        concat nav_btn(CHEVRON_L,
          I18n.t("modelrails_ui.calendar.prev_month", default: "Previous month"),
          "click->calendar#prevMonth")
        concat content_tag(:span, @month.strftime("%B %Y"), class: MONTH_CLS,
          data: { calendar_target: "monthLabel" })
        concat nav_btn(CHEVRON_R,
          I18n.t("modelrails_ui.calendar.next_month", default: "Next month"),
          "click->calendar#nextMonth")
      end
    end

    def nav_btn(path, label, action)
      content_tag(:button, type: "button", class: NAV_BTN,
        "aria-label": label, data: { action: action }) { chevron(path) }
    end

    # The whole month is one grid widget; its accessible name is the month/year
    # caption so a screen reader announces "June 2026 grid" on entry.
    def month_grid
      content_tag(:div,
        role: "grid",
        "aria-label": @month.strftime("%B %Y"),
        class: GRID_CLS,
        data: { calendar_target: "grid" }) do
        concat day_of_week_row
        concat safe_join(weeks.map { |week| week_row(week) })
      end
    end

    def day_of_week_row
      content_tag(:div, role: "row", class: ROW_CLS) do
        safe_join(weekday_headers.map { |day|
          content_tag(:div, role: "columnheader", class: DOW_CLS) do
            content_tag(:abbr, day[:abbr], title: day[:title], class: "no-underline")
          end
        })
      end
    end

    def week_row(week)
      content_tag(:div, role: "row", class: ROW_CLS) do
        safe_join(week.map { |date| day_cell(date) })
      end
    end

    def day_cell(date)
      selected = @selected && date == @selected
      content_tag(:div,
        role: "gridcell",
        class: CELL_CLS,
        "aria-selected": selected.to_s) do
        day_button(date, selected)
      end
    end

    def day_button(date, selected)
      outside  = date.month != @month.month
      is_today = date == Date.today
      disabled = (@min && date < @min) || (@max && date > @max)

      classes = cn(DAY_BASE,
        selected ? DAY_SEL : DAY_NORMAL,
        is_today ? DAY_TODAY : nil,
        # Today's heading-weight text emphasis applies only off a fill: on a
        # selected (bg-interactive) cell, DAY_SEL's text-text-on-interactive must
        # win, else heading text on the fill fails dark-mode contrast (#266 regression).
        (is_today && !selected) ? "text-text-heading" : nil,
        outside  ? DAY_MUTED : nil,
        disabled ? DAY_DISABLED : nil)

      content_tag(:button,
        date.day.to_s,
        type: "button",
        class: classes,
        # Full localized date is the button's accessible name; the bare day
        # number is not enough out of column/row context.
        "aria-label": I18n.t("modelrails_ui.calendar.day",
          default: date.strftime("%-d %B %Y"), date: date.strftime("%-d %B %Y")),
        "aria-pressed": selected.to_s,
        # Today/selected are announced via aria-current/aria-selected on the cell;
        # mark today here too so SR users hear it on the button itself.
        "aria-current": (is_today ? "date" : nil),
        # Roving tabindex: exactly the active day is tabbable; the rest are
        # reachable only via the controller's arrow-key handlers.
        tabindex: (date == roving_day ? "0" : "-1"),
        disabled: disabled || nil,
        data: { action: keyboard_actions, calendar_date_param: date.iso8601 })
    end

    # Arrow/Home/End/PageUp/PageDown move focus across the grid; click/Enter/Space
    # select. The controller implements the roving-tabindex bookkeeping.
    def keyboard_actions
      "click->calendar#selectDay keydown->calendar#navigate"
    end

    # The single day in the tab order: the selected day if it's in this month,
    # else today if shown, else the first of the month — so Tab always lands on a
    # sensible cell and arrow keys take over from there.
    def roving_day
      return @selected if @selected && @selected.month == @month.month && @selected.year == @month.year

      today = Date.today
      return today if today.month == @month.month && today.year == @month.year

      @month
    end

    def weeks
      first = @month.beginning_of_month
      start = first - ((first.wday - @week_offset) % 7)
      (start..(start + 41)).to_a.each_slice(7).to_a
    end

    def weekday_headers
      base = Date.new(2026, 1, 4) # a Sunday — anchor for localized day names
      (0..6).map do |i|
        day = base + ((i + @week_offset) % 7)
        { abbr: day.strftime("%a")[0, 2], title: day.strftime("%A") }
      end
    end

    def chevron(path)
      content_tag(:svg,
        content_tag(:path, nil, d: path, "stroke-linecap": "round", "stroke-linejoin": "round"),
        xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24",
        fill: "none", stroke: "currentColor", "stroke-width": "2",
        class: "size-4", "aria-hidden": "true")
    end
  end
end
