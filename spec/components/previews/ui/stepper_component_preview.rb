# frozen_string_literal: true

module UI
  # # Stepper
  #
  # An ordered progress indicator: an `<ol>` of steps shown as complete, current,
  # or pending. It communicates *where you are* in a multi-step flow — it is NOT
  # interactive navigation (the steps are not links/buttons).
  #
  # ## Accessibility contract
  # - **Guarantees:** an `<ol>` with an i18n `aria-label` ("Progress"); the current
  #   step carries `aria-current="step"`, complete/pending circles carry an i18n
  #   `aria-label` ("Completed" / "Pending"), and the check icon + `●`/`○` glyphs
  #   are decorative.
  # - **You supply:** a `label:` per step and a `status:` of `:complete`,
  #   `:current`, or `:pending` (defaults to `:pending`).
  #
  # ## Modes
  # `orientation: :horizontal` (default) · `orientation: :vertical`.
  # @logical_path Feedback & Status
  class StepperComponentPreview < ViewComponent::Preview
    include UIHelper

    # A horizontal 3-step flow: one complete, one current, one pending.
    def default
    end

    # The same flow stacked vertically, with optional per-step descriptions.
    def vertical
    end

    # Edit `orientation` live to compare horizontal vs vertical layout.
    # @param orientation select [horizontal, vertical]
    def playground(orientation: :horizontal)
      ui :stepper, orientation: orientation.to_sym, steps: [
        { label: "Account", status: :complete },
        { label: "Profile", status: :current },
        { label: "Confirm", status: :pending }
      ]
    end
  end
end
