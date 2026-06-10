# frozen_string_literal: true

module UI
  # # BottomNav
  #
  # A fixed mobile bottom navigation bar: a **named** `<nav>` landmark pinned to the
  # bottom of the viewport, holding a row of icon+label destinations.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named `<nav>` landmark (i18n default "Bottom navigation",
  #   override via `label:`), the AAA `focus-ring` on every item, and
  #   `aria-current="page"` on the active item.
  # - **You supply:** `items:` (`[{ label:, href:, active:, icon: }]`).
  # @logical_path Navigation
  class BottomNavComponentPreview < ViewComponent::Preview
    include UIHelper

    # A three-tab bar with the first item active and inline SVG icons.
    def default
    end
  end
end
