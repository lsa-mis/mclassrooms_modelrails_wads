# frozen_string_literal: true

module UI
  # # Textarea
  #
  # A multi-line text control with AAA field styling, `aria-invalid`, and
  # `aria-describedby` wiring baked in.
  #
  # **Normally reached via `f.text_area :attr`.**
  # The `TailwindFormBuilder` renders this control together with its label, help text,
  # error message, and full ARIA wiring. Use `ui :textarea` directly only when you need
  # a bare control outside a managed form.
  #
  # ## Use when
  # - You need a multi-line input — comments, descriptions, free-text notes.
  # - You are building a standalone editor outside a `form_with` block.
  #
  # ## Don't use when
  # - You are inside a `form_with` block — call `f.text_area :attr` instead so the
  #   label, error message, and ARIA associations come for free.
  # - A single line is enough — use `f.text_field` / `ui :input`.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA border and focus-ring tokens, `min-h-[var(--form-input-height)]`
  #   touch target, `aria-invalid="true"` when `invalid: true`, and
  #   `aria-describedby` wired when `describedby:` is supplied.
  # - **You supply (when standalone):** a visible `<label>` associated via `for:/id:`,
  #   and a `name:` attribute. The form builder supplies both automatically.
  # @logical_path Forms & Inputs
  class TextareaComponentPreview < ViewComponent::Preview
    include UIHelper

    # Prescribed path: render inside a form via the TailwindFormBuilder, which owns
    # the label, help text, error message, and ARIA wiring.
    def in_a_form; end

    # Multi-line input at rest — the baseline appearance.
    def default; end

    # Error state: red border + `aria-invalid="true"`. In a real form the builder
    # sets both automatically when an ActiveModel error is present.
    def invalid; end

    # ## Don't — hand-rolled `<textarea>` tag
    #
    # Writing a bare `<textarea>` in ERB skips the AAA styling tokens, the focus ring,
    # and the automatic ARIA wiring. Always go through the form builder
    # (`f.text_area :attr`) or, for standalone controls, `ui :textarea`.
    # @label Don't · raw <textarea> tag
    def dont_raw_textarea; end
  end
end
