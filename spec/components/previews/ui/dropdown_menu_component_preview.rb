# frozen_string_literal: true

module UI
  # # Dropdown menu
  #
  # A button that opens a menu of actions (WAI-ARIA APG menu-button), driven by the
  # `menu` Stimulus controller. Open with the trigger; navigate with ↑/↓/Home/End or
  # type-ahead; Enter/Space/click activates; Escape/Tab/outside-click closes.
  #
  # ## Accessibility contract
  # - **Guarantees:** `aria-haspopup="menu"` + synced `aria-expanded`; `role="menu"`
  #   named by the trigger; `role="menuitem"` items with roving tabindex.
  # - **You supply:** a `with_trigger` slot and `with_item` slots; `aria_label:` for
  #   icon-only triggers.
  # @logical_path Overlays
  class DropdownMenuComponentPreview < ViewComponent::Preview
    include UIHelper

    # Standard menu: a button trigger and a labelled menu with items, a disabled item,
    # a separator, and a link item.
    def basic
    end

    # `side:` and `align:` edge-align the menu to the trigger.
    def positioned
    end

    # Edit `side` and `align` live to explore placement.
    # @param side select [bottom, top]
    # @param align select [start, end]
    def playground(side: :bottom, align: :start)
      render_with_template(locals: { side: side.to_sym, align: align.to_sym })
    end
  end
end
