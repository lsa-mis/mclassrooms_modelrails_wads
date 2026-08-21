# frozen_string_literal: true

module UI
  # # Date Picker
  #
  # A disclosure button that opens an inline calendar popover, driven by the
  # `date-picker` Stimulus controller shipped alongside this component. The button is
  # the accessible control (it carries the selected-date label); the calendar grid
  # itself is owned by `UI::CalendarComponent` (this component does not re-implement it).
  #
  # ## Use when
  # - A form needs a single date and a month-grid affordance is friendlier than a bare
  #   `<input type="date">`.
  #
  # ## Don't use when
  # - You only need a native date field with no custom calendar — use `input` with
  #   `type: "date"`.
  # - You need a range (two bounds) — compose two pickers or a range calendar.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<button>` trigger with `aria-haspopup="dialog"`,
  #   `aria-expanded` (kept in sync by the controller), and `aria-controls` → the
  #   popover id; the popover is a `role="dialog"` named by `label:`; a visible caption
  #   `<label>`-style heading and a format hint wired via `aria-describedby`; the
  #   decorative calendar icon is `aria-hidden`; Escape and outside-click close the
  #   popover and return focus to the trigger. The trigger carries the offset
  #   `focus-ring` (never a box-shadow ring).
  # - **You supply:** an optional `label:` (the field caption / popover name; defaults
  #   to an i18n string) and a `name:` if the value must post back.
  #
  # value:       Date or nil — initial selected date
  # name:        form field name for the hidden input
  # label:       visible caption + popover/trigger accessible name (i18n default)
  # placeholder: trigger text when no date is selected (i18n default)
  # format:      :long | :short | :iso — Ruby strftime for the initial label AND the
  #              format hint shown to the user (fail-loud on an unknown key)
  # min/max:     Date bounds passed to the calendar
  class DatePickerComponent < ApplicationComponent
    WRAPPER = "relative inline-block"
    CAPTION = "mb-1.5 block text-sm font-medium text-text-heading"
    HINT_CLS = "mt-1.5 block text-sm text-text-muted"
    TRIGGER = "flex h-9 w-48 cursor-pointer items-center gap-2 rounded-md border border-border-strong " \
               "bg-surface-raised px-3 text-sm text-text-heading shadow-xs focus-ring transition " \
               "aria-expanded:border-border-focus"
    ICON_CLS = "size-4 shrink-0 text-text-muted"
    # Placement is CSS anchor positioning: `position: fixed` (containing block = the
    # viewport) tethered to the trigger via `anchor-name`/`position-anchor`. Being
    # viewport-positioned is what lets the panel be promoted to the top layer, so a
    # sticky/backdrop-blur ancestor cannot bury it (app/javascript/overlays/top_layer.js).
    POPOVER = "z-50 hidden w-max rounded-lg border border-border bg-surface-overlay p-0 shadow-md data-[open=true]:block mt-1 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_span-right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:left-0"

    # strftime patterns and the human-readable format hint, keyed by `format:`.
    FORMATS = {
      long: { strftime: "%B %-d, %Y", hint: "MMMM D, YYYY" },
      short: { strftime: "%-m/%-d/%Y", hint: "M/D/YYYY" },
      iso: { strftime: "%Y-%m-%d", hint: "YYYY-MM-DD" }
    }.freeze

    def initialize(value: nil, name: nil, label: nil, placeholder: nil, format: :long, min: nil, max: nil,
      **html_attrs)
      @value = value
      @name = name
      @format = coerce_enum(:format, format, FORMATS)
      @label = label || I18n.t("modelrails_ui.date_picker.label", default: "Choose date")
      @placeholder = placeholder || I18n.t("modelrails_ui.date_picker.placeholder", default: "Pick a date")
      @min = min
      @max = max
      @id = html_attrs.delete(:id) || "date-picker-#{SecureRandom.hex(4)}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      caller_data = @html_attrs.delete(:data) || {}
      content_tag(:div,
        class: cn(WRAPPER, @extra_class),
        style: "anchor-name: --#{@id}",
        data: { controller: "date-picker" }.merge(caller_data),
        **@html_attrs) do
        concat caption
        concat hidden_input if @name
        concat trigger_button
        concat hint
        concat calendar_popover
      end
    end

    private

    def trigger_id = "#{@id}-trigger"
    def popover_id = "#{@id}-popover"
    def hint_id = "#{@id}-hint"

    def caption
      content_tag(:label, @label, id: "#{@id}-caption", class: CAPTION, for: trigger_id)
    end

    def hint
      content_tag(:span, I18n.t("modelrails_ui.date_picker.hint", pattern: format_hint,
        default: "Date format: %{pattern}"), id: hint_id, class: HINT_CLS)
    end

    def format_hint = FORMATS.fetch(@format)[:hint]

    def hidden_input
      tag.input(type: "hidden", name: @name,
        value: @value&.iso8601,
        data: { date_picker_target: "hidden" })
    end

    def trigger_button
      label_text = @value ? @value.strftime(FORMATS.fetch(@format)[:strftime]) : @placeholder
      content_tag(:button, type: "button",
        id: trigger_id,
        class: TRIGGER,
        "aria-expanded": "false",
        "aria-haspopup": "dialog",
        "aria-controls": popover_id,
        "aria-label": @label,
        "aria-describedby": hint_id,
        data: {
          date_picker_target: "trigger",
          action: "click->date-picker#toggle keydown->date-picker#triggerKeydown"
        }) do
        concat calendar_icon
        concat content_tag(:span, label_text, data: { date_picker_target: "label" })
      end
    end

    def calendar_popover
      content_tag(:div,
        id: popover_id,
        class: POPOVER,
        style: "position-anchor: --#{@id}",
        role: "dialog",
        "aria-label": @label,
        tabindex: "-1",
        data: {
          date_picker_target: "popover",
          action: "calendar:change->date-picker#dateSelected keydown.esc->date-picker#closeAndFocus"
        }) do
        render UI::CalendarComponent.new(
          selected: @value,
          min: @min,
          max: @max
        )
      end
    end

    def calendar_icon
      content_tag(:svg,
        content_tag(:path, nil,
          d: "M8 2v3m8-3v3M3.5 8h17M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z",
          "stroke-linecap": "round", "stroke-linejoin": "round"),
        xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24",
        fill: "none", stroke: "currentColor", "stroke-width": "2",
        class: ICON_CLS, "aria-hidden": "true")
    end

    def coerce_enum(name, value, map)
      key = value.to_sym
      return key if map.key?(key)

      raise ArgumentError,
        "UI::DatePicker unknown #{name}: #{value.inspect} (allowed: #{map.keys.join(", ")})"
    end
  end
end
