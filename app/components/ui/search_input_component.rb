# frozen_string_literal: true

module UI
  # # SearchInput
  #
  # A single-line `<input type="search">` with a decorative magnifier icon, AAA
  # field styling, and an always-present accessible name. Use it for one-off search
  # boxes, filters, and command bars that live **outside** a managed `form_with`.
  #
  # ## Use when
  # - A standalone search / filter box: a list filter, a command palette trigger,
  #   a site-search field in a header.
  #
  # ## Don't use when
  # - You are inside a `form_with` block — call `f.search_field :attr` so the label,
  #   error message, and ARIA associations come from the form builder for free.
  # - You need the full sortable/filterable table toolbar — use `data_table`, which
  #   embeds its own search control.
  #
  # ## Accessibility contract
  # - **Guarantees:** an accessible name on every instance. A placeholder is only a
  #   hint and is NOT an accessible name, so the control always carries an `aria-label`
  #   (defaulting to the i18n `modelrails_ui.search_input.label`). The magnifier icon
  #   is `aria-hidden` (decorative). The control sits at the AAA 44 px target floor
  #   (`h-11`, WCAG 2.5.5) with AAA border and focus-ring tokens.
  # - **You supply:** on error, `invalid: true` (sets `aria-invalid`) plus `describedby:`
  #   pointing at the hint/error message's id; a custom `label:` when "Search" is wrong.
  #
  # This mirrors the form-control API of `input`/`checkbox` (`required:` -> required +
  # aria-required, `invalid:` -> aria-invalid, `describedby:` -> aria-describedby).
  #
  # No variant axis (single appearance), so there is no `coerce_variant` fail-loud
  # guard here -- unlike the enum-driven components (alert, button).
  class SearchInputComponent < ApplicationComponent
    WRAPPER   = "relative w-full"
    ICON_WRAP = "pointer-events-none absolute inset-y-0 left-3 flex items-center text-text-muted"
    SEARCH_PATH = "m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z"
    # h-11 keeps the control at the AAA 44px target floor (WCAG 2.5.5).
    INPUT_BASE = "h-11 w-full min-w-0 rounded-md border border-border-strong bg-surface-raised py-1 pl-9 pr-3 text-base text-text-heading shadow-xs " \
                 "transition-[color,box-shadow] outline-none " \
                 "placeholder:text-text-muted " \
                 "focus-visible:border-border-focus focus-visible:ring-[3px] focus-visible:ring-interactive-focus " \
                 "aria-invalid:border-danger-border aria-invalid:ring-danger " \
                 "disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 " \
                 "md:text-sm "

    # First-class accessibility/form params so the component is usable standalone:
    #   label:       the accessible name (aria-label); defaults to the i18n "Search"
    #                string -- a placeholder is only a hint, never an accessible name.
    #   required:    sets the HTML `required` attribute AND `aria-required="true"`
    #   invalid:     sets `aria-invalid="true"` (drives the error border/ring tokens)
    #   describedby: sets `aria-describedby` (link to hint/error element ids)
    # Everything else (name, id, value, data-*, ...) passes through.
    def initialize(placeholder: "Search…", label: nil, required: false, invalid: false, describedby: nil, **html_attrs)
      @placeholder = placeholder
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
