# frozen_string_literal: true

module UI
  # # Number Input
  #
  # A native `<input type="number">` with AAA field styling and `aria-invalid` /
  # `aria-describedby` / `required` wiring baked in.
  #
  # **Normally reached via `f.number_field`.** The `TailwindFormBuilder` renders this
  # control together with its label, help text, error message, and full ARIA wiring.
  # Use `ui :number_input` directly only when you need a bare control outside a managed
  # form.
  #
  # ## Use when
  # - You need a numeric entry (quantity, price, age) with `min` / `max` / `step`
  #   constraints, **outside** a `form_with` block.
  # - You are assembling a custom form builder that wraps this component yourself.
  #
  # ## Don't use when
  # - You are inside a `form_with` block — call `f.number_field :attr` instead so the
  #   label, error message, and ARIA associations come for free.
  # - You need a slider with a visible range — use `ui :range`.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA border and focus-ring tokens, a `min-h-[var(--form-input-height)]`
  #   44 px touch target (no sub-44px custom buttons — the field is the only target),
  #   an `id` always emitted, `aria-invalid="true"` when `invalid: true`,
  #   `aria-describedby` wired when `describedby:` is supplied, and
  #   `required` + `aria-required="true"` when `required: true`.
  # - **You supply (when standalone):** a visible `<label>` associated via `for:/id:`,
  #   and a `name:` attribute. The form builder supplies both automatically.
  # @logical_path Forms & Inputs
  class NumberInputComponentPreview < ViewComponent::Preview
    include UIHelper

    # A bounded numeric input with min/max/step constraints — the baseline appearance.
    def default
    end

    # Required input: emits the native `required` attribute plus `aria-required="true"`.
    def required
    end

    # Error state: `aria-invalid="true"` plus `aria-describedby` wired to a sibling
    # error message. In a real form the form builder sets both automatically when an
    # ActiveModel error is present.
    def invalid
    end

    # ## Don't — hand-rolled `<input type="number">` tag
    #
    # Writing a bare `<input type="number">` in ERB skips the AAA styling tokens, the
    # 44px touch target, the focus ring, and the automatic ARIA wiring the component
    # provides. Always go through the form builder (`f.number_field :attr`) or, for
    # standalone controls, `ui :number_input`.
    # @label Don't · raw <input> tag
    def dont_raw_input
    end
  end
end
