# frozen_string_literal: true

module UI
  # # File Input
  #
  # A file-picker control with AAA field styling, `aria-invalid`, and
  # `aria-describedby` wiring baked in. This component extended the app's original
  # plain `file_field` helper — adding the ARIA attributes the helper lacked — so it
  # is the canonical way to render file pickers everywhere in the app.
  #
  # **Normally reached via `f.file_field :attr`.**
  # The `TailwindFormBuilder` renders this control together with its label, help text,
  # error message, and full ARIA wiring. Use `ui :file_input` directly only when you
  # need a bare control outside a managed form.
  #
  # ## Use when
  # - You need users to upload a file: avatars, attachments, imports.
  # - You are building a standalone dropzone or custom upload widget outside a form.
  #
  # ## Don't use when
  # - You are inside a `form_with` block — call `f.file_field :attr` instead so the
  #   label, error message, and ARIA associations come for free.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA border and focus-ring tokens, `min-h-[var(--form-input-height)]`
  #   44 px touch target, `aria-invalid="true"` when `invalid: true`, and
  #   `aria-describedby` wired when `describedby:` is supplied. These ARIA attributes
  #   were absent on the legacy plain `file_field` — this component fills that gap.
  # - **You supply:** a visible `<label>` associated via `for:/id:`. The form builder
  #   supplies it automatically.
  class FileInputComponentPreview < ViewComponent::Preview
    include UIHelper

    # Prescribed path: render inside a form via the TailwindFormBuilder, which owns
    # the label, help text, error message, and ARIA wiring.
    def in_a_form; end

    # Generic file picker — no type restriction.
    def default; end

    # Restricts the OS file picker to images; the browser enforces the `accept` hint.
    def images_only; end

    # Allows selecting more than one file in a single pick. The field name should end
    # in `[]` when paired with a Rails controller that expects an array.
    def multiple; end

    # ## Don't — hand-rolled `<input type="file">` tag
    #
    # A bare `<input type="file">` in ERB skips the AAA styling tokens, the focus ring,
    # and the `aria-invalid` / `aria-describedby` attributes this component adds.
    # Always go through the form builder (`f.file_field :attr`) or, for standalone
    # controls, `ui :file_input`.
    # @label Don't · raw <input type="file"> tag
    def dont_raw_file_input; end
  end
end
