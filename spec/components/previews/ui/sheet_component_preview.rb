# frozen_string_literal: true

module UI
  # # Sheet
  #
  # A native `<dialog>` side panel — pinned to a chosen edge and sliding in
  # from that edge. A flexible overlay for navigation, filters, and secondary
  # forms. Behavior lives in the `modal` Stimulus controller with per-side
  # slide transform values.
  #
  # ## Use when
  # - A side panel is the right pattern for navigation, filters, or secondary
  #   forms that slide in from a screen edge.
  #
  # ## Don't use when
  # - A centered confirm gate is needed — use `alert_dialog`.
  # - A bottom sheet is the right pattern — use `drawer`.
  #
  # ## Accessibility contract
  # - **Guarantees:** native `<dialog>` with `role="dialog"` and `aria-modal="true"`,
  #   `aria-labelledby` wired to the heading, `aria-describedby` when `description:`
  #   is given, a 44px accessible close button, focus trap + restore via the `modal`
  #   controller, and native Escape via the controller's cancel handler.
  # - **You supply:** a `title:` (required — the accessible name). Actions belong in
  #   the `with_footer` slot. The `with_trigger` slot provides the open button. Pass
  #   `side:` to choose which edge the panel slides in from (`:right` default).
  # @logical_path Overlays
  class SheetComponentPreview < ViewComponent::Preview
    include UIHelper

    # Default side panel sliding in from the right edge. The `with_trigger` slot
    # renders inside the `modal` controller wrapper so clicking the button calls
    # `modal#open` automatically.
    def basic
    end

    # Side panel sliding in from the left edge — useful for navigation menus or
    # site-wide drawers that conventionally originate from the left.
    # @label Left-side panel
    def side_left
    end

    # Side panel sliding in from the bottom edge.
    # @label Bottom panel
    def side_bottom
    end

    # Edit `side` live to slide the panel in from any edge.
    # @param side select [top, right, bottom, left]
    def playground(side: :right)
      render(UI::SheetComponent.new(title: "Filters", side: side.to_sym)) do |c|
        c.with_trigger { "Open sheet" }
        "Panel slides in from the #{side} edge. Change the param to explore placement."
      end
    end
  end
end
