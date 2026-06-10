# frozen_string_literal: true

module UI
  # # Drawer
  #
  # A native `<dialog>` bottom sheet — full-width, pinned to the bottom edge,
  # sliding up on open. A lightweight mobile-friendly overlay for secondary
  # actions and supplemental content. Behavior lives in the `modal` Stimulus
  # controller with slide-up/down transform values.
  #
  # ## Use when
  # - A bottom sheet is the right pattern for mobile-friendly secondary actions
  #   or content that slides in from the bottom edge.
  #
  # ## Don't use when
  # - A centered confirm gate is needed — use `alert_dialog`.
  # - A side panel is needed — use `sheet`.
  #
  # ## Accessibility contract
  # - **Guarantees:** native `<dialog>` with `role="dialog"` and `aria-modal="true"`,
  #   `aria-labelledby` wired to the heading, `aria-describedby` when `description:`
  #   is given, a 44px accessible close button, focus trap + restore via the `modal`
  #   controller, and native Escape via the controller's cancel handler.
  # - **You supply:** a `title:` (required — the accessible name). Actions belong in
  #   the `with_footer` slot. The `with_trigger` slot provides the open button.
  # @logical_path Overlays
  class DrawerComponentPreview < ViewComponent::Preview
    include UIHelper

    # Standard bottom sheet: trigger button, title, description, and body content.
    # The `with_trigger` slot renders inside the `modal` controller wrapper so
    # clicking the button calls `modal#open` automatically.
    def basic
    end

    # Bottom sheet with footer actions — useful for supplemental forms or action
    # menus where the user should confirm or dismiss.
    # @label With footer actions
    def with_footer
    end
  end
end
