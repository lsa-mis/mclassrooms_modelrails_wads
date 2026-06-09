# frozen_string_literal: true

module UI
  # # ScrollArea
  #
  # A fixed-height (or fixed-width) scrollable container with a thin, themed
  # scrollbar styled via CSS custom properties — no plugin needed under Tailwind v4.
  #
  # ## Use when
  # - Long content must live in a bounded box (a list, a code block, a panel) the
  #   user scrolls within.
  #
  # ## Don't use when
  # - The content is already focusable throughout (links/buttons) — the browser
  #   scrolls to follow focus. Pass `focusable: false` to skip the extra tab stop.
  #
  # ## Accessibility contract
  # - **Guarantees (WCAG 2.1.1):** a focusable region is a `tabindex="0"` tab stop
  #   with a `focus-ring` indicator and a `role="region"` accessible name, so
  #   keyboard-only users can focus and arrow-scroll it and AT announces it.
  # - **You supply:** an accessible name via `aria_label:` or `aria_labelledby:`.
  class ScrollAreaComponentPreview < ViewComponent::Preview
    include UIHelper

    # A fixed-height vertical scroll area with long content. It is a keyboard tab
    # stop (Tab to it, then arrow to scroll) and named via `aria_label:`.
    def default
    end

    # A horizontal scroll area — the axis follows `orientation: :horizontal`.
    def horizontal
    end

    # ## Don't — a scroll region with no keyboard access
    #
    # `focusable: false` removes the tab stop AND the accessible name. A keyboard-only
    # user cannot reach or scroll this region (WCAG 2.1.1 failure) unless every child
    # is itself focusable. Only opt out when the content is fully keyboard-reachable.
    # @label Don't · no keyboard access
    def dont_no_keyboard_access
    end
  end
end
