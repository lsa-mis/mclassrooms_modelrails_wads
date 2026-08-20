# frozen_string_literal: true

module UI
  class FileInputComponent < ApplicationComponent
    # Applies the app's `.form-file` class (file:* styling + aria-invalid error
    # utilities, defined in application.css). a11y params added so the builder
    # can wire aria-invalid/describedby — closing the gap where the app's plain
    # file_field skipped ARIA.

    # Per-file pill for the show_selection list: the badge chip shape plus the
    # proven [:soft, :primary] color cell (bg-interactive-subtle + text-interactive
    # — the same AAA pairing UI::BadgeComponent ships; badges have no soft-neutral
    # cell, and inventing a new color pairing here is off-limits).
    PILL = "inline-flex w-fit shrink-0 items-center justify-center gap-1 overflow-hidden rounded-full " \
           "border border-transparent px-2 py-0.5 text-xs font-medium whitespace-nowrap " \
           "bg-interactive-subtle text-interactive"

    # accept:   MIME types or extensions, e.g. "image/*" or ".pdf,.docx"
    # multiple: allow selecting multiple files
    # required/invalid/describedby: form + a11y wiring (see UI::InputComponent)
    # show_selection:   also render the selected file names as pills plus an sr-only
    #                   live-region announcement, synced by the `file-input` Stimulus
    #                   controller (default false = bare input, byte-unchanged) —
    #                   the native control alone only shows a count ("3 files")
    # selection_labels: strings merged over the defaults, with `%{count}`/`%{names}`
    #                   placeholders substituted client-side
    def initialize(accept: nil, multiple: false, required: false, invalid: false, describedby: nil,
                   show_selection: false, selection_labels: {}, **html_attrs)
      @accept = accept
      @multiple = multiple
      @required = required
      @invalid = invalid
      @describedby = describedby
      @show_selection = show_selection
      @selection_labels = default_selection_labels.merge(selection_labels.transform_keys(&:to_sym))
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      # Default: a bare native input (output byte-identical to the pre-selection
      # component). With `show_selection:` the input is wrapped with the pill list,
      # pill <template>, and sr-only status region the `file-input` controller drives.
      return content_tag(:input, nil, **input_attrs, **@html_attrs) unless @show_selection

      content_tag(:div, data: {
        controller: "file-input",
        file_input_one_value: @selection_labels[:one],
        file_input_many_value: @selection_labels[:many],
        file_input_none_value: @selection_labels[:none]
      }) do
        safe_join([ wired_input, selection_list, pill_template, status_region ])
      end
    end

    private

    # Gem parity note: the gem ships hardcoded English defaults ("i18n lives in the
    # host app, not the gem"); this app IS the host, so the defaults resolve through
    # I18n like the other vendored components' strings (combobox, data_table).
    def default_selection_labels
      {
        one: I18n.t("modelrails_ui.file_input.one_selected", default: "1 file selected: %{names}"),
        many: I18n.t("modelrails_ui.file_input.many_selected", default: "%{count} files selected: %{names}"),
        none: I18n.t("modelrails_ui.file_input.none_selected", default: "No files selected")
      }
    end

    def input_attrs
      attrs = { type: "file", class: cn("form-file", @extra_class) }
      attrs[:accept] = @accept if @accept
      attrs[:multiple] = true if @multiple
      if @required
        attrs[:required] = true
        attrs["aria-required"] = "true"
      end
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      attrs
    end

    # The input keeps every attr it has in bare mode; the controller wiring is
    # merged into `data:` so a caller-supplied `data:` hash survives.
    def wired_input
      attrs = input_attrs.merge(@html_attrs)
      attrs[:data] = (attrs[:data] || {}).merge(
        file_input_target: "input", action: "change->file-input#update"
      )
      content_tag(:input, nil, **attrs)
    end

    # Starts hidden; the controller un-hides it only while it holds pills.
    def selection_list
      content_tag(:ul, nil, hidden: true, class: "mt-2 flex flex-wrap gap-1.5",
        data: { file_input_target: "list" })
    end

    def pill_template
      content_tag(:template, data: { file_input_target: "pill" }) do
        content_tag(:li, nil, class: PILL)
      end
    end

    # Always present in the DOM: a live region that exists from page load announces
    # reliably; un-hiding a populated one does not — so status is separate from the
    # visible list.
    def status_region
      content_tag(:span, nil, class: "sr-only", "aria-live": "polite",
        data: { file_input_target: "status" })
    end
  end
end
