# frozen_string_literal: true

module UI
  # # Mega menu
  #
  # A disclosure button that reveals a full-width panel of grouped **navigation
  # links**. Unlike `dropdown_menu`/`menubar` (which use the WAI-ARIA `menu`
  # pattern), this is a disclosure + named `<nav>` region — the panel holds ordinary
  # anchor links that keep native Tab/anchor behavior.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<button>` trigger with `aria-haspopup`, synced
  #   `aria-expanded`, and `aria-controls` → the panel; the panel is a `<nav>`
  #   landmark named by the trigger label; AAA `focus-ring` on the trigger and every
  #   link; a decorative (`aria-hidden`) chevron; outside-click dismissal.
  # - **You supply:** a `label:` and one or more `with_column(heading:, items:)` blocks.
  # @logical_path Navigation
  class MegaMenuComponentPreview < ViewComponent::Preview
    include UIHelper

    # A two-column products menu of navigation links.
    def default
    end
  end
end
