# frozen_string_literal: true

module UI
  # # Sidebar
  #
  # A collapsible application sidebar: an `<aside>` rail containing a **named**
  # `<nav>` landmark with grouped items. The rail collapses to an icon strip
  # (purely visual — labels stay in the accessibility tree).
  #
  # ## Remembering the collapse choice
  # The toggle writes a `sidebar_collapsed` cookie. Render the rail in the remembered
  # shape on the first paint by passing the helper — otherwise the sidebar paints
  # expanded and JS collapses it after, which the visitor sees as a flash:
  #
  #     ui :sidebar, collapsed: sidebar_collapsed?
  #
  # Pass `remember: false` for a sidebar whose state should not outlive the page.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named `<nav>` landmark (i18n default, override via `label:`),
  #   an i18n-labelled toggle carrying `aria-expanded` + `aria-controls` (the collapse
  #   state is otherwise invisible to assistive tech — `data-collapsed` is CSS-only),
  #   AAA `focus-ring` on the toggle and every item, and `aria-current="page"` on the
  #   active item.
  # - **You supply:** groups/items (label, href, optional icon, active).
  # @display background bleed
  # @logical_path Navigation
  class SidebarComponentPreview < ViewComponent::Preview
    include UIHelper

    # Expanded rail with grouped nav items.
    def default
    end

    # The collapsed rail — labels clip to icons but remain in the a11y tree. Hover or
    # focus an item for the hint bubble, which is aria-hidden precisely because the
    # label is still there: announcing both would name every item twice.
    def collapsed
    end

    # `remember: false` — the toggle still works, but the choice does not outlive the
    # page. For a sidebar whose shape is decided by the screen it is on, not the visitor.
    def not_remembered
    end
  end
end
