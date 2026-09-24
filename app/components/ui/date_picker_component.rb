# frozen_string_literal: true

module UI
  # A typeable date field with a calendar popover beside it, driven by the `date-picker` Stimulus controller shipped alongside this component.
  # Usage, options and the accessibility contract: docs/components/date_picker.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class DatePickerComponent < ApplicationComponent
    WRAPPER = "relative inline-block"
    CAPTION = "mb-1.5 block text-sm font-medium text-text-heading"
    HINT_CLS = "mt-1.5 block text-sm text-text-muted"
    # The typed path is the PRIMARY control; the calendar is the secondary one.
    # h-11/w-11 on the trigger keeps it at the AAA 44px target floor now that it is
    # icon-only rather than a full-width labelled button.
    GROUP = "flex items-stretch gap-1"
    INPUT = "h-11 w-40 rounded-md border border-border-strong bg-surface-raised px-3 text-sm " \
            "text-text-heading shadow-xs focus-ring transition " \
            "aria-[invalid=true]:border-2 aria-[invalid=true]:border-danger "
    TRIGGER = "flex size-11 shrink-0 cursor-pointer items-center justify-center rounded-md " \
               "border border-border-strong bg-surface-raised text-text-heading shadow-xs focus-ring transition " \
               "aria-expanded:border-border-focus"
    ERROR_CLS = "mt-1.5 block text-sm text-danger"
    ICON_CLS = "size-4 shrink-0 text-text-muted"
    # Placement is CSS anchor positioning: `position: fixed` (containing block = the
    # viewport) tethered to the trigger via `anchor-name`/`position-anchor`. Being
    # viewport-positioned is what lets the panel be promoted to the top layer, so a
    # sticky/backdrop-blur ancestor cannot bury it (app/javascript/overlays/top_layer.js).
    POPOVER = "z-50 hidden w-max max-w-[calc(100vw-2rem)] rounded-lg border border-border bg-surface-overlay p-0 shadow-md data-[open=true]:block mt-1 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_span-right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:left-0"

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
        data: {
          controller: "date-picker",
          date_picker_invalid_message_value: I18n.t("modelrails_ui.date_picker.invalid",
            pattern: format_hint, default: "Enter a date as %{pattern}."),
          date_picker_range_message_value: I18n.t("modelrails_ui.date_picker.out_of_range",
            default: "That date is outside the allowed range.")
        }.merge(caller_data),
        **@html_attrs) do
        concat caption
        concat hidden_input if @name
        concat content_tag(:div, safe_join([ text_input, trigger_button ]), class: GROUP)
        concat hint
        concat error_region
        concat calendar_popover
      end
    end

    private

    def trigger_id = "#{@id}-trigger"
    def input_id = "#{@id}-input"
    def error_id = "#{@id}-error"
    def popover_id = "#{@id}-popover"
    def hint_id = "#{@id}-hint"

    # Bound to the TEXT INPUT, not the trigger. `<label for>` may only name a
    # labelable element, so pointing it at a <button> named nothing at all — and
    # left the control a person actually types into unlabelled.
    def caption
      content_tag(:label, @label, id: "#{@id}-caption", class: CAPTION, for: input_id)
    end

    def hint
      content_tag(:span, I18n.t("modelrails_ui.date_picker.hint", pattern: format_hint,
        default: "Date format: %{pattern}"), id: hint_id, class: HINT_CLS)
    end

    def format_hint = FORMATS.fetch(@format)[:hint]

    # The typed path. The hidden input stays canonical — this box is parsed on
    # commit and written back formatted — so a caller reads one value whichever
    # way it was set.
    #
    # `change` and Enter, never `input`: parsing per keystroke rewrites the box
    # under someone who is still typing.
    def text_input
      tag.input(
        type: "text",
        id: input_id,
        value: @value&.strftime(FORMATS.fetch(@format)[:strftime]),
        placeholder: @placeholder,
        inputmode: "numeric",
        autocomplete: "off",
        spellcheck: "false",
        "aria-describedby": "#{hint_id} #{error_id}",
        "aria-invalid": "false",
        class: INPUT,
        data: {
          date_picker_target: "input",
          date_picker_format: @format.to_s,
          date_picker_min: @min&.iso8601,
          date_picker_max: @max&.iso8601,
          action: "change->date-picker#commit keydown->date-picker#commitOnEnter"
        }.compact
      )
    end

    # Present and EMPTY from first render: a live region inserted already carrying
    # its text is inserted-with-content, and assistive tech drops it.
    def error_region
      content_tag(:span, nil, id: error_id, class: ERROR_CLS, role: "status", "aria-live": "polite",
        data: { date_picker_target: "error" })
    end

    def hidden_input
      tag.input(type: "hidden", name: @name,
        value: @value&.iso8601,
        data: { date_picker_target: "hidden" })
    end

    # Icon-only now that the caption names the input, so it needs a name of its
    # own — and one that says what it DOES, since "Due date" is already taken by
    # the field beside it.
    def trigger_button
      content_tag(:button, calendar_icon,
        type: "button",
        id: trigger_id,
        class: TRIGGER,
        "aria-expanded": "false",
        "aria-haspopup": "dialog",
        "aria-controls": popover_id,
        "aria-label": I18n.t("modelrails_ui.date_picker.open_calendar", name: @label,
          default: "Open calendar for %{name}"),
        data: {
          date_picker_target: "trigger",
          action: "click->date-picker#toggle keydown->date-picker#triggerKeydown"
        })
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
