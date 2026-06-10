# frozen_string_literal: true

module UI
  # # Checkbox
  #
  # A single labelled native checkbox — the form-control pattern-setter. Always
  # carries an `id` so the `<label for=...>` association never breaks.
  #
  # ## Use when
  # - A single on/off choice tied to a label ("Accept terms", "Remember me").
  #
  # ## Don't use when
  # - It's an immediate-effect setting toggle — use `switch`.
  # - It's a mutually-exclusive set of options — use `radio_group`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a labelled, keyboard-operable checkbox with an AAA focus ring;
  #   the clickable label provides the larger AAA target.
  # - **You supply:** a `label` and, on error, `invalid: true` + `describedby:`.
  # @logical_path Forms & Inputs
  class CheckboxComponentPreview < ViewComponent::Preview
    include UIHelper

    # A labelled, unchecked checkbox.
    def default
    end

    # Pre-checked.
    def checked
    end

    # Error state — aria-invalid wired to a described-by error message.
    def invalid
    end

    # Non-interactive — the label dims via the peer-disabled hook.
    def disabled
    end

    # ## Don't — an unlabelled checkbox
    #
    # No `label` and no `aria-label` leaves an unlabelled control — screen-reader
    # users hear no purpose. Always pass a `label` (or an `aria-label`).
    # @label Don't · no label
    def dont_no_label
    end
  end
end
