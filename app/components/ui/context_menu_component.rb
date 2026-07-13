# frozen_string_literal: true

module UI
  # # Context menu
  #
  # A menu of actions opened by right-clicking — or Shift+F10 / the ContextMenu key while
  # the host has keyboard focus — on a host region, implementing the WAI-ARIA APG menu
  # pattern via the shared `menu` Stimulus controller. Positioning is JS: the panel is
  # `fixed` and the controller's `openAt` sets `top`/`left` from the pointer (or the host's
  # rect for the keyboard path). The keyboard model (roving tabindex, type-ahead,
  # Escape/Tab/outside-click dismissal with focus restore) is identical to `dropdown_menu`.
  #
  # ## Use when
  # - A region (a row, a card, a canvas, a file tile) exposes contextual actions on right-click.
  #
  # ## Don't use when
  # - A visible trigger button should open the menu — use `dropdown_menu`.
  #
  # ## Accessibility contract
  # - **Guarantees:** the host is focusable (`tabindex="0"`) with `aria-haspopup="menu"`,
  #   `aria-expanded` (kept in sync) and `aria-controls`; opens on `contextmenu` AND
  #   Shift+F10 / the ContextMenu key (WCAG 2.1.1 keyboard parity); a `role="menu"` panel
  #   named by the host (or `label:`); `role="menuitem"` items with roving tabindex;
  #   Escape/Tab/outside-click close with focus restored to the host.
  # - **You supply:** a `with_trigger` slot (the right-clickable region) and one or more
  #   `with_item` slots.
  class ContextMenuComponent < ApplicationComponent
    renders_one :trigger

    # Each item is a real menuitem button (or an anchor when `href:` is given). `disabled:`
    # marks it `aria-disabled` (skipped by keyboard nav; activation rejected). `separator:`
    # renders a divider in source order. Caller `data:`/`class:` merge without clobbering
    # the menu wiring (el splats last). Identical to dropdown_menu's item model.
    renders_many :items, ->(separator: false, disabled: false, href: nil, **attrs, &block) do
      next content_tag(:div, "", role: "separator", class: SEPARATOR) if separator

      tag_name = href ? :a : :button
      caller_data = attrs.delete(:data) || {}
      el = {
        role: "menuitem",
        tabindex: "-1",
        class: cn(ITEM, attrs.delete(:class)),
        data: { menu_target: "item", action: "click->menu#activate" }.merge(caller_data)
      }
      el[:href] = href if href
      el[:type] = "button" unless href
      el[:"aria-disabled"] = "true" if disabled
      # `el` splats LAST so the ARIA/Stimulus wiring (role/tabindex/class/data) always wins
      # over caller attrs — callers may add attrs but cannot break the menu contract.
      content_tag(tag_name, capture(&block), **attrs, **el)
    end

    # Panel is `fixed` (positioned by the controller's `openAt`, not anchor positioning —
    # a context menu tethers to a point, not an element).
    PANEL = "fixed z-50 min-w-[8rem] overflow-hidden rounded-md border border-border " \
            "bg-surface-overlay p-1 text-text-body shadow-md outline-none"

    # Menu item — focus-visible AND hover share the highlight (roving focus must be visible);
    # disabled items inert + de-emphasised on semantic tokens; SVG normalised. (Identical to
    # dropdown_menu; AAA contrast adjudicated by the app 0b CI axe, not locally.)
    ITEM = "relative flex w-full cursor-pointer select-none items-center gap-2 rounded-sm " \
           "px-2 py-1.5 text-sm outline-none " \
           "hover:bg-surface-sunken hover:text-text-heading " \
           "focus-visible:bg-surface-sunken focus-visible:text-text-heading " \
           "aria-disabled:pointer-events-none aria-disabled:opacity-60 aria-disabled:cursor-not-allowed " \
           "[&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4 " \
           "[&_svg:not([class*='text-'])]:text-text-muted"
    SEPARATOR = "-mx-1 my-1 h-px bg-border"

    # id:         menu id (auto-generated if omitted; → aria-controls)
    # label:      explicit menu accessible name (aria-label). Omit to name the menu by the
    #             host region (aria-labelledby) — pass `label:` when the host is large/verbose.
    def initialize(id: nil, label: nil, **html_attrs)
      @id = id || "context-menu-#{SecureRandom.hex(4)}"
      @trigger_id = "#{@id}-trigger"
      @label = label
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      raise ArgumentError, "UI::ContextMenuComponent requires a with_trigger slot" unless trigger?

      content_tag(:div, **wrapper_attrs) do
        safe_join([ trigger_region, menu_panel ])
      end
    end

    private

    def wrapper_attrs
      caller_data = @html_attrs.delete(:data) || {}
      {
        class: cn("relative", @extra_class),
        data: { controller: "menu", action: "click@document->menu#closeOnClickOutside" }.merge(caller_data)
      }.merge(@html_attrs)
    end

    def trigger_region
      content_tag(:div, trigger,
        id: @trigger_id,
        # min 44px: the trigger is TABBABLE (right-click/keyboard surface) —
        # a real target under the AAA floor (a11y gate, 2026-07-13).
        # role=button: aria-haspopup/aria-expanded are NOT allowed on a
        # role-less div (axe aria-allowed-attr, critical); the trigger is
        # operable (tabindex + keydown) and named by its contents.
        role: "button",
        class: "select-none inline-flex min-h-11 min-w-11 items-center",
        tabindex: "0",
        "aria-haspopup": "menu",
        "aria-expanded": "false",
        "aria-controls": @id,
        data: { menu_target: "trigger", action: "contextmenu->menu#openAt keydown->menu#openContextKey" })
    end

    def menu_panel
      content_tag(:div, safe_join(items),
        id: @id,
        role: "menu",
        "aria-labelledby": (@trigger_id unless @label),
        "aria-label": @label,
        tabindex: "-1",
        hidden: true,
        style: "top: 0; left: 0",
        data: { menu_target: "menu", action: "keydown->menu#navigate" },
        class: PANEL)
    end
  end
end
