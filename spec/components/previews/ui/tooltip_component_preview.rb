# frozen_string_literal: true

module UI
  # # Tooltip
  #
  # A short text hint describing the element it wraps. Shows on hover AND keyboard
  # focus; `aria-describedby` wires the `role="tooltip"` bubble to the focusable wrapper;
  # Escape dismisses (WCAG 1.4.13) via the shared `floating` controller.
  #
  # ## Accessibility contract
  # - **Guarantees:** hover + focus reveal; `role="tooltip"` + `aria-describedby`;
  #   Escape-dismiss; `pointer-events-none` bubble.
  # - **You supply:** `text:` (the hint) and the trigger content.
  # @logical_path Overlays
  class TooltipComponentPreview < ViewComponent::Preview
    include UIHelper

    # Hover or keyboard-focus the trigger to reveal the hint; Escape dismisses it.
    def basic
    end

    # Edit `text` and `side` live to explore placement.
    # @param text text
    # @param side select [top, bottom, left, right, top_left, top_right, bottom_left, bottom_right]
    def playground(text: "Saved to your library", side: :top)
      render_with_template(locals: { text: text, side: side.to_sym })
    end
  end
end
