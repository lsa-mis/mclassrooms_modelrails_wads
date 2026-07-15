# frozen_string_literal: true

module UI
  # # Form Draft Notice
  #
  # Visual states of the draft-recovery notice. Behavior (save/recover) is
  # proven by spec/system/form_drafts/*; this preview must not depend on a
  # live draft key.
  #
  # ## Use when
  # - A form has draft-recovery enabled via the `form-draft` Stimulus controller.
  #
  # ## Accessibility contract
  # - **Guarantees:** a hidden warning chip (revealed by controller when a draft
  #   exists), dual action buttons, and a stable sr-only status region for
  #   announcing recovery/discard results.
  # - **You supply:** nothing — the partial renders with defaults for preview;
  #   production callers never pass `revealed:` (controller manages visibility).
  #
  # @logical_path Forms & Inputs
  class FormDraftComponentPreview < ViewComponent::Preview
    include UIHelper

    # Revealed chip + both buttons, as a user with a saved draft sees it.
    def default
      render_with_template
    end
  end
end
