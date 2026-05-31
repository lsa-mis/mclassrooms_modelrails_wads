# frozen_string_literal: true

module UI
  class InputComponent < ApplicationComponent
    # Styling matches the host app's TailwindFormBuilder field constants exactly,
    # so swapping the builder to render this component is visually invisible.
    # (FIELD_BASE / FIELD_NORMAL / FIELD_ERROR in app/form_builders/tailwind_form_builder.rb)
    BASE   = "block w-full rounded-md border px-3 py-2 placeholder:text-text-muted " \
             "focus:outline-none focus:ring-2 min-h-[var(--form-input-height)]"
    NORMAL = "border-border-strong bg-surface-raised text-text-heading focus:ring-interactive-focus"
    ERROR  = "border-danger ring-2 ring-danger bg-danger-surface text-danger focus:ring-danger"

    # First-class accessibility/form params so the component is usable standalone
    # AND drivable by the form builder:
    #   required:    sets the HTML `required` attribute AND `aria-required="true"`
    #   invalid:     applies the error styling AND sets `aria-invalid="true"`
    #   describedby: sets `aria-describedby` (link to hint/error element ids)
    # Everything else (id, name, value, placeholder, data-*, …) passes through.
    def initialize(type: "text", required: false, invalid: false, describedby: nil, **html_attrs)
      @type = type
      @required = required
      @invalid = invalid
      @describedby = describedby
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:input, nil, **input_attrs)
    end

    private

    def input_attrs
      attrs = { type: @type, class: cn(BASE, @invalid ? ERROR : NORMAL, @extra_class) }
      if @required
        attrs[:required] = true
        attrs["aria-required"] = "true"
      end
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      attrs.merge(@html_attrs)
    end
  end
end
