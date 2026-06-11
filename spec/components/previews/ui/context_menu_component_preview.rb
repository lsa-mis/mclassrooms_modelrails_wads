# frozen_string_literal: true

module UI
  # # Context menu
  #
  # A menu of actions opened by right-clicking — or Shift+F10 / the ContextMenu key while
  # the host has focus — on a host region, via the shared `menu` controller. No enum params
  # (pointer-positioned), so no @param playground.
  #
  # ## Accessibility contract
  # - **Guarantees:** focusable host (`aria-haspopup="menu"` + synced `aria-expanded`);
  #   `contextmenu` + Shift+F10 open; `role="menu"` named by the host; `role="menuitem"`
  #   items with roving tabindex.
  # - **You supply:** a `with_trigger` host slot and `with_item` slots.
  #
  # ## Related
  # `dropdown_menu` · `menubar`
  # @logical_path Overlays
  class ContextMenuComponentPreview < ViewComponent::Preview
    include UIHelper

    # Right-click (or focus + Shift+F10) the card to open the menu.
    def basic
    end
  end
end
