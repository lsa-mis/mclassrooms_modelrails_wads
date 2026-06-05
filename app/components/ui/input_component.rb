# frozen_string_literal: true

module UI
  class InputComponent < ApplicationComponent
    # Applies the app's `.form-field` class; error styling is attribute-driven via
    # `.form-field[aria-invalid]` in application.css. The component sets `aria-invalid`
    # when `invalid:`.

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
      attrs = { type: @type, class: cn("form-field", @extra_class) }
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
