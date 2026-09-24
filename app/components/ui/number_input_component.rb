# frozen_string_literal: true

module UI
  # A native `<input type="number">` with AAA field styling and the shared form-control ARIA wiring (`invalid:` / `describedby:` / `required:`).
  # Usage, options and the accessibility contract: docs/components/number_input.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class NumberInputComponent < ApplicationComponent
    # `min-h-input` (44px) replaces the old fixed `h-9` (36px)
    # so the control meets the AAA 2.5.5 target-size floor and aligns with sibling
    # form fields. All colors are AAA semantic tokens — no raw Tailwind palette.
    BASE = "block w-full min-w-0 rounded-md border border-border-strong bg-transparent px-3 py-1 text-base shadow-xs " \
           "min-h-input " \
           "transition-[color,box-shadow] outline-none " \
           "placeholder:text-text-muted " \
           "focus-visible:border-border-focus focus-ring " \
           "aria-invalid:border-2 aria-invalid:border-danger " \
           "disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 " \
           "[appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none " \
           "md:text-sm"

    # First-class accessibility/form params so the component is usable standalone AND
    # drivable by the form builder (mirrors the input/checkbox/select API):
    #   required:    sets the HTML `required` attribute AND `aria-required="true"`
    #   invalid:     sets `aria-invalid="true"` (error styling fires off the attribute)
    #   describedby: sets `aria-describedby` (link to hint/error element ids)
    # min / max / step / value are the native number-input attributes; everything
    # else (name, data-*, …) passes through.
    def initialize(min: nil, max: nil, step: nil, value: nil,
                   required: false, invalid: false, describedby: nil, **html_attrs)
      @min   = min
      @max   = max
      @step  = step
      @value = value
      @required = required
      @invalid = invalid
      @describedby = describedby
      # Always resolve an id so an external label association never breaks: explicit
      # id → sanitized name → an object-based fallback (mirrors checkbox/select).
      @id = html_attrs[:id] || html_attrs[:name]&.gsub(/\W/, "_") || "number_input_#{object_id}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:input, nil, **input_attrs)
    end

    private

    def input_attrs
      attrs = @html_attrs.merge(type: "number", id: @id, class: cn(BASE, @extra_class))
      attrs[:min]   = @min   unless @min.nil?
      attrs[:max]   = @max   unless @max.nil?
      attrs[:step]  = @step  unless @step.nil?
      attrs[:value] = @value unless @value.nil?
      if @required
        attrs[:required] = true
        attrs["aria-required"] = "true"
      end
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      attrs
    end
  end
end
