# frozen_string_literal: true

module UI
  # # Sidebar
  #
  # A collapsible application sidebar: an `<aside>` rail containing a **named**
  # `<nav>` landmark with grouped items. The rail collapses to an icon strip
  # (purely visual — labels stay in the accessibility tree).
  #
  # ## Accessibility contract
  # - **Guarantees:** a named `<nav>` landmark (i18n default, override via `label:`),
  #   an i18n-labelled toggle, AAA `focus-ring` on the toggle and every item, and
  #   `aria-current="page"` on the active item.
  # - **You supply:** groups/items (label, href, optional icon, active).
  class SidebarComponentPreview < ViewComponent::Preview
    include UIHelper

    # Expanded rail with grouped nav items.
    def default
    end

    # The collapsed rail — labels clip to icons but remain in the a11y tree.
    def collapsed
    end
  end
end
