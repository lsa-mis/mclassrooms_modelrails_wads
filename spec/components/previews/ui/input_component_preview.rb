# frozen_string_literal: true

module UI
  # # Input
  #
  # A single-line text control with AAA field styling, `aria-invalid`, and
  # `aria-describedby` wiring baked in.
  #
  # **Normally reached via `f.text_field`, `f.email_field`, `f.password_field`, etc.**
  # The `TailwindFormBuilder` renders this control together with its label, help text,
  # error message, and full ARIA wiring. Use `ui :input` directly only when you need
  # a bare control outside a managed form.
  #
  # ## Use when
  # - You are building a one-off search box, filter, or inline editor that lives
  #   **outside** a `form_with` block.
  # - You are assembling a custom form builder that wraps this component yourself.
  #
  # ## Don't use when
  # - You are inside a `form_with` block — call `f.text_field :attr` instead so the
  #   label, error message, and ARIA associations come for free.
  # - You need a multi-line field — use `f.text_area` / `ui :textarea`.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA border and focus-ring tokens, `min-h-[var(--form-input-height)]`
  #   44 px touch target, `aria-invalid="true"` when `invalid: true`, and
  #   `aria-describedby` wired when `describedby:` is supplied.
  # - **You supply (when standalone):** a visible `<label>` associated via `for:/id:`,
  #   and a `name:` attribute. The form builder supplies both automatically.
  # @logical_path Forms & Inputs
  class InputComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Prescribed path: render inside a form via the TailwindFormBuilder, which owns
    # the label, help text, error message, and ARIA wiring. This is what you paste
    # into a real form.
    def in_a_form; end

    # Plain text input — the baseline appearance.
    def default; end

    # Email input with required styling; the browser also validates format on submit.
    def required; end

    # Error state: red border + `aria-invalid="true"`. In a real form the form builder
    # sets both automatically when an ActiveModel error is present.
    def invalid; end

    # @!endgroup

    # @!group Reference

    # ## Don't — hand-rolled `<input>` tag
    #
    # Writing a bare `<input>` in ERB skips the AAA styling tokens, the focus ring,
    # and the automatic ARIA wiring the component provides. Always go through the form
    # builder (`f.text_field :attr`) or, for standalone controls, `ui :input`.
    # @label Don't · raw <input> tag
    def dont_raw_input; end

    # @!endgroup
  end
end
