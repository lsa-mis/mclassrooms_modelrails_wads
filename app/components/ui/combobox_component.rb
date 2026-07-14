# frozen_string_literal: true

module UI
  # # Combobox
  #
  # An autocomplete select: a text input that filters a dropdown of options and
  # writes the chosen value to a hidden field for form submission. Filtering and
  # keyboard navigation live in the `combobox` Stimulus controller shipped
  # alongside this component.
  #
  # ## Use when
  # - You need a single-choice control over a long, known list where free-text
  #   filtering beats scrolling a native `<select>`.
  #
  # ## Don't use when
  # - The list is short and needs no search — use a native `select`.
  # - It's a keyboard-first launcher for *actions* (the ⌘K pattern) — use `command`.
  #
  # ## Accessibility contract (WAI-ARIA APG combobox + listbox)
  # - **Guarantees:** the text input is a `role="combobox"` with `aria-expanded`,
  #   `aria-controls` (→ the list) and `aria-autocomplete="list"`, named by an i18n
  #   `aria-label` (override via `label:`). The popup is a named `role="listbox"`;
  #   each option is a `role="option"` with `aria-selected`. The controller tracks
  #   the highlighted option via `aria-activedescendant` (DOM focus stays on the
  #   input — ↑/↓/Home/End move the active option, Enter selects it, Escape closes).
  #   The input and options carry the AAA `focus-ring`; the empty state is an i18n
  #   live region.
  # - **You supply:** `name:` (hidden-field name), `options:` (array of
  #   `{ value:, label: }`), optional `value:` (pre-selected), `placeholder:`,
  #   `label:` (accessible name), and `size:`.
  #
  # ## Sizes
  # `sm` · `md` · `lg` — the input height.
  class ComboboxComponent < ApplicationComponent
    # `focus-ring` is the AAA offset outline (never a clipped box-shadow ring).
    INPUT = "flex w-full rounded-md border border-border-strong bg-transparent px-3 py-2 text-sm shadow-xs " \
            "text-text-body placeholder:text-text-muted focus-ring"
    PANEL = "absolute z-50 top-full left-0 mt-1 w-full overflow-hidden rounded-md border border-border " \
            "bg-surface-overlay text-text-body shadow-md"
    LIST = "max-h-[200px] overflow-y-auto p-1"
    # `focus-ring` keeps the AAA offset outline if an option takes DOM focus;
    # `aria-selected:` styles the controller-tracked active option for pointer +
    # keyboard parity.
    OPTION = "relative flex w-full cursor-pointer select-none items-center rounded-sm " \
             "px-2 py-1.5 text-sm text-text-body focus-ring hover:bg-surface-sunken hover:text-text-heading " \
             "aria-selected:bg-surface-sunken aria-selected:text-text-heading"
    EMPTY = "py-4 text-center text-sm text-text-muted"

    # Input height per size.
    SIZES = {
      sm: "h-11",
      md: "h-11",
      lg: "h-11"
    }.freeze

    def initialize(name:, options: [], value: nil, placeholder: nil, label: nil, size: :md, **html_attrs)
      @name = name
      @options = options
      @value = value&.to_s
      @placeholder = placeholder
      @label = label
      @size = coerce_size(size)
      @extra_class = html_attrs.delete(:class)
      # Merge the controller wiring into any caller `data:` so a passed-through
      # `data:` attr can't clobber `data-controller` and silently break Stimulus.
      @data = {
        controller: "combobox",
        action: "click@document->combobox#closeOnClickOutside"
      }.merge(html_attrs.delete(:data) || {})
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, class: cn("relative", @extra_class), data: @data, **@html_attrs) do
        concat hidden_input
        concat text_input
        concat dropdown
      end
    end

    private

    LIST_ID = "combobox-list"

    def accessible_name
      @label || I18n.t("modelrails_ui.combobox.label", default: "Search and select an option")
    end

    def placeholder_text
      @placeholder || I18n.t("modelrails_ui.combobox.placeholder", default: "Select…")
    end

    def hidden_input
      tag.input(type: "hidden", name: @name, value: @value, data: { combobox_target: "hidden" })
    end

    def text_input
      selected_label = @options.find { |o| o[:value].to_s == @value }&.dig(:label)
      tag.input(
        type: "text",
        role: "combobox",
        placeholder: placeholder_text,
        value: selected_label,
        "aria-label": accessible_name,
        "aria-expanded": "false",
        "aria-controls": LIST_ID,
        "aria-autocomplete": "list",
        autocomplete: "off",
        spellcheck: "false",
        class: cn(INPUT, SIZES.fetch(@size)),
        data: {
          combobox_target: "input",
          action: "focus->combobox#open input->combobox#filter keydown->combobox#navigate"
        }
      )
    end

    def dropdown
      content_tag(:div, listbox, data: { combobox_target: "panel" }, hidden: true, class: PANEL)
    end

    def listbox
      content_tag(:div,
        id: LIST_ID,
        role: "listbox",
        "aria-label": accessible_name,
        class: LIST,
        data: { combobox_target: "list" }) do
        concat options_list
        concat content_tag(:div,
          I18n.t("modelrails_ui.combobox.empty", default: "No results found."),
          class: EMPTY,
          role: "status",
          data: { combobox_target: "empty" },
          hidden: true)
      end
    end

    def options_list
      safe_join(@options.map { |opt|
        content_tag(:button, opt[:label],
          type: "button",
          role: "option",
          "aria-selected": (opt[:value].to_s == @value).to_s,
          class: OPTION,
          data: {
            combobox_target: "option",
            combobox_value: opt[:value],
            combobox_label: opt[:label],
            action: "click->combobox#select"
          })
      })
    end

    # Fail loud on an unknown size in development/test so misuse is caught
    # immediately; fall back to :md in production so a bad size never 500s a page.
    # (Rails.respond_to?(:env) stays correct in the gem's Rails-less render tests,
    # which define Rails without booting Rails.env.)
    def coerce_size(size)
      size = size.to_sym
      return size if SIZES.key?(size)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::ComboboxComponent: unknown size #{size.inspect}. " \
          "Expected one of: #{SIZES.keys.join(", ")}."
      end

      :md
    end
  end
end
