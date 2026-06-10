# frozen_string_literal: true

module UI
  # # Resizable
  #
  # Drag-to-resize panel layout — two panels separated by a **window splitter**.
  # The handle follows the APG window-splitter pattern: grab it with the mouse, or
  # focus it and drive it with the keyboard.
  #
  # ## Accessibility contract
  # - **Guarantees (WCAG 2.1.1):** each handle is a focusable `role="separator"`
  #   tab stop with the `focus-ring` indicator, an i18n `aria-label`, the
  #   `aria-orientation` it splits across, and a live `aria-valuenow/valuemin/
  #   valuemax` range. Arrow keys resize it (← → horizontal, ↑ ↓ vertical);
  #   Home/End jump to its min/max.
  # - **You supply:** panels with optional `min`/`max`/`default` percentages.
  # @logical_path Layout
  class ResizableComponentPreview < ViewComponent::Preview
    include UIHelper

    # Side-by-side panels. Tab to the divider, then Arrow Left/Right to resize it
    # (or drag it with the mouse).
    def default
    end

    # A vertical (stacked) split — the divider is horizontal and Arrow Up/Down
    # resizes it.
    def vertical
    end
  end
end
