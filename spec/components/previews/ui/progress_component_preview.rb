# frozen_string_literal: true

module UI
  # # Progress
  #
  # A determinate progress bar for a known percentage. For indeterminate waits, use
  # `spinner`.
  #
  # ## Use when
  # - You can express progress as a value between 0 and `max`.
  #
  # ## Don't use when
  # - The wait is indeterminate (use `spinner`), or the bar has no accessible name
  #   and no nearby text (pass `label:`).
  #
  # ## Accessibility contract
  # - **Guarantees:** `role="progressbar"` + `aria-valuenow`/`min`/`max`, value clamped.
  # - **You supply:** `label:` when no visible text names the bar.
  # @logical_path Feedback & Status
  class ProgressComponentPreview < ViewComponent::Preview
    include UIHelper

    # Half-filled bar.
    def default
    end

    # Named bar — `label:` becomes the accessible name.
    def with_label
    end

    # Fully complete.
    def complete
    end

    # ## Don't — unlabeled progress bar
    #
    # This bar has no `label:` and no surrounding text, so it is unnamed for screen
    # readers — AT users hear a value with no idea what is progressing. Pass `label:`.
    # @label Don't · unlabeled
    def dont_unlabeled
    end
  end
end
