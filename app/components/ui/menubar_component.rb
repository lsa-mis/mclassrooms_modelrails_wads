# frozen_string_literal: true

module UI
  # # Menubar
  #
  # A horizontal application menubar (WAI-ARIA APG menubar) — a `role="menubar"` of top-level
  # items, each opening a submenu. The bar is one tab stop (roving tabindex); ←/→ move between
  # items, ↓/Enter open a submenu. Each submenu reuses the shared `menu` Stimulus controller;
  # a thin `menubar` controller coordinates the bar and drives submenus via Stimulus outlets.
  #
  # ## Use when
  # - An app-level command bar (File / Edit / View …) where one row exposes several menus.
  #
  # ## Don't use when
  # - A single trigger opens one menu — use `dropdown_menu`.
  #
  # ## Accessibility contract
  # - **Guarantees:** `role="menubar"` (named by `label:`); bar items `role="menuitem"` +
  #   `aria-haspopup="menu"` + synced `aria-expanded` + `aria-controls`, roving tabindex (one
  #   tab stop); full keyboard (←/→ wrap, Home/End, type-ahead, ↓/Enter opens submenu,
  #   ↑ opens to last, Escape closes to the bar item, ←/→ from a submenu follows to the
  #   adjacent menu). Submenus are `role="menu"` with roving menuitems.
  # - **You supply:** one or more `with_menu(label:)` slots, each with `with_item` slots.
  class MenubarComponent < ApplicationComponent
    renders_many :menus, "UI::MenubarMenuComponent"

    BAR = "flex items-center gap-1 rounded-md border border-border bg-surface-raised p-1 shadow-xs"

    # label: the menubar's accessible name (aria-label), e.g. "Main". Required — a generic
    # default would silently pass axe's name-present check while leaving the role=menubar
    # container under-named (and ambiguous when a page has more than one).
    def initialize(label:, **html_attrs)
      @label = label
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      caller_data = @html_attrs.delete(:data) || {}
      content_tag(:div, safe_join(menus),
        role: "menubar",
        "aria-label": @label,
        class: cn(BAR, @extra_class),
        data: {
          controller: "menubar",
          menubar_menu_outlet: "[data-menubar-item]",
          action: "keydown->menubar#navigate focusin->menubar#syncRoving"
        }.merge(caller_data),
        **@html_attrs)
    end
  end
end
