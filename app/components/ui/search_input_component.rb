# frozen_string_literal: true

module UI
  # A single-line `<input type="search">` with a decorative magnifier icon, AAA field styling, and an always-present accessible name.
  # Usage, options and the accessibility contract: docs/components/search_input.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class SearchInputComponent < ApplicationComponent
    WRAPPER   = "relative w-full"
    ICON_WRAP = "pointer-events-none absolute inset-y-0 left-3 flex items-center text-text-muted"
    SEARCH_PATH = "m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z"
    # h-11 keeps the control at the AAA 44px target floor (WCAG 2.5.5).
    INPUT_BASE = "h-11 w-full min-w-0 rounded-md border border-border-strong bg-surface-raised py-1 pl-9 pr-3 text-base text-text-heading shadow-xs " \
                 "transition-[color,box-shadow] outline-none " \
                 "placeholder:text-text-muted " \
                 "focus-visible:border-border-focus focus-ring " \
                 "aria-invalid:border-2 aria-invalid:border-danger " \
                 "disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 " \
                 "md:text-sm "

    # First-class accessibility/form params so the component is usable standalone:
    #   label:       the accessible name (aria-label); defaults to the i18n "Search"
    #                string -- a placeholder is only a hint, never an accessible name.
    #   required:    sets the HTML `required` attribute AND `aria-required="true"`
    #   invalid:     sets `aria-invalid="true"` (drives the error border/ring tokens)
    #   describedby: sets `aria-describedby` (link to hint/error element ids)
    # Everything else (name, id, value, data-*, ...) passes through.
    def initialize(placeholder: nil, label: nil, required: false, invalid: false, describedby: nil, **html_attrs)
      @placeholder = placeholder || I18n.t("modelrails_ui.search_input.placeholder", default: "Search…")
      @label       = label || I18n.t("modelrails_ui.search_input.label", default: "Search")
      @required    = required
      @invalid     = invalid
      @describedby = describedby
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:div, class: WRAPPER) do
        concat icon_span
        concat content_tag(:input, nil, **input_attrs)
      end
    end

    private

    def input_attrs
      attrs = {
        type: "search",
        placeholder: @placeholder,
        "aria-label": @label,
        class: cn(INPUT_BASE, @extra_class)
      }
      if @required
        attrs[:required] = true
        attrs["aria-required"] = "true"
      end
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      attrs.merge(@html_attrs)
    end

    def icon_span
      svg = content_tag(:svg,
        content_tag(:path, nil, d: SEARCH_PATH, "stroke-linecap": "round", "stroke-linejoin": "round"),
        xmlns: "http://www.w3.org/2000/svg",
        viewBox: "0 0 24 24",
        fill: "none",
        stroke: "currentColor",
        "stroke-width": "1.5",
        class: "size-4",
        "aria-hidden": "true")
      content_tag(:span, svg, class: ICON_WRAP)
    end
  end
end
