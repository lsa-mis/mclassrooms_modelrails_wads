# frozen_string_literal: true

module UI
  # # Alert Dialog
  #
  # A native `<dialog role="alertdialog">` confirm modal — center-scaled, focus-trapped,
  # `aria-modal`, with native Escape (cancel event) and `::backdrop`. Use when a user
  # must explicitly confirm or cancel before proceeding. Behavior lives in the `modal`
  # Stimulus controller.
  #
  # **Prefer `UI::AlertDialogComponent` over a plain `dialog` whenever the user must
  # confirm or cancel an action** — the `role="alertdialog"` causes screen readers to
  # announce the dialog immediately (assertive) rather than waiting for the user to
  # discover it.
  #
  # ## Use when
  # - A choice must be confirmed before proceeding — especially for destructive or
  #   irreversible actions (delete, reset, revoke access).
  #
  # ## Don't use when
  # - A non-blocking notice is sufficient — use the toast / notification system.
  # - You need a general form or multi-step flow — use `dialog`.
  #
  # ## Accessibility contract
  # - **Guarantees:** native `<dialog>` with `role="alertdialog"` and `aria-modal="true"`,
  #   `aria-labelledby` wired to the heading, `aria-describedby` wired to the message
  #   when `description:` is given, an accessible close button, and focus trap + restore
  #   via the `modal` Stimulus controller.
  # - **You supply:** a `title:` (required — the accessible name) and footer action
  #   buttons in the `with_footer` slot. The `with_trigger` slot provides the open button.
  # @logical_path Overlays
  class AlertDialogComponentPreview < ViewComponent::Preview
    include UIHelper

    # Standard confirm gate: trigger button, title, description, and Confirm / Cancel
    # actions in the footer. The `with_trigger` slot renders inside the `modal` controller
    # wrapper so clicking the button calls `modal#open` automatically.
    def basic
    end

    # Destructive confirm — title "Delete?", danger-styled primary action.
    # Use whenever the confirmed action is irreversible (delete, revoke, reset).
    # @label Destructive confirm
    def confirm_destructive
    end
  end
end
