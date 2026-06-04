# frozen_string_literal: true

module UI
  # # Number Input
  #
  # A native `<input type="number">` with AAA field styling and the shared
  # form-control ARIA wiring (`invalid:` / `describedby:` / `required:`).
  #
  # **Normally reached via `f.number_field`.** The `TailwindFormBuilder` renders this
  # control together with its label, help text, error message, and full ARIA wiring.
  # Use `ui :number_input` directly only when you need a bare control outside a managed
  # form.
  #
  # ## Use when
  # - You need a numeric entry (quantity, price, age) with `min` / `max` / `step`
  #   constraints, outside a `form_with` block.
  # - You are assembling a custom form builder that wraps this component yourself.
  #
  # ## Don't use when
  # - You are inside a `form_with` block — call `f.number_field :attr` instead so the
  #   label, error message, and ARIA associations come for free.
  # - You need a slider with a visible range — use `ui :range`.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA border and focus-ring tokens, a `min-h-[var(--form-input-height)]`
  #   44 px touch target, an `id` always emitted so an external `<label for=...>` can
  #   target it, `aria-invalid="true"` when `invalid: true`, `aria-describedby` wired
  #   when `describedby:` is supplied, and `required` + `aria-required="true"` when
  #   `required: true`.
  # - **You supply (when standalone):** a visible `<label>` associated via `for:/id:`,
  #   and a `name:` attribute. The form builder supplies both automatically.
  #
  # The WebKit spin-buttons are intentionally hidden (`[appearance:textfield]` +
  # `::-webkit-*-spin-button`); there are NO custom +/- stepper buttons, so the only
  # interactive target is the field itself (held at the 44px floor above). With no
  # variant axis (single appearance) there is also no `coerce_variant` fail-loud guard
  # here, unlike the enum-driven components (alert, button).
  class NumberInputComponent < ApplicationComponent
    # `min-h-[var(--form-input-height)]` (44px) replaces the old fixed `h-9` (36px)
    # so the control meets the AAA 2.5.5 target-size floor and aligns with sibling
    # form fields. All colors are AAA semantic tokens — no raw Tailwind palette.
    BASE = "block w-full min-w-0 rounded-md border border-border-strong bg-transparent px-3 py-1 text-base shadow-xs " \
           "min-h-[var(--form-input-height)] " \
           "transition-[color,box-shadow] outline-none " \
           "placeholder:text-text-muted " \
           "focus-visible:border-border-focus focus-visible:ring-[3px] focus-visible:ring-interactive-focus " \
           "aria-invalid:border-danger-border aria-invalid:ring-danger " \
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
