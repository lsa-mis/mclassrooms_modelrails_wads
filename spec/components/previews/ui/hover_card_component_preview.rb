# frozen_string_literal: true

module UI
  # # Hover Card
  #
  # A rich supplemental card revealed on hover AND keyboard focus of its trigger.
  # `focus-within` keeps it open while you Tab through its content; Escape dismisses
  # (WCAG 1.4.13). Use for enhancement, not as the only path to the content.
  #
  # ## Accessibility contract
  # - **Guarantees:** hover + focus-within reveal; card content Tab-reachable while open;
  #   Escape-dismiss; `role="group"` + `aria-label` when `label:` given.
  # - **You supply:** a `with_trigger` slot (a focusable link/button) and card content.
  class HoverCardComponentPreview < ViewComponent::Preview
    include UIHelper

    # Hover or focus the trigger to reveal the card; Tab through its links; Escape dismisses.
    def basic
    end

    # Edit `side` and `label` live.
    # @param label text
    # @param side select [bottom, top, left, right, top_left, top_right, bottom_left, bottom_right]
    def playground(label: "User card", side: :bottom)
      render_with_template(locals: { label: label, side: side.to_sym })
    end
  end
end
