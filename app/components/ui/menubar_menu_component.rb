# frozen_string_literal: true

module UI
  # # Menubar menu
  #
  # One top-level menu of a `menubar`: a bar-item button (`role="menuitem"`,
  # `aria-haspopup="menu"`) plus its submenu (`role="menu"`). The submenu IS a `menu`
  # controller (reused via EXTRA_STIMULUS) — same item model + behavior as `dropdown_menu`;
  # positioning is CSS anchor positioning (the panel tethers to the bar item). Always used
  # inside `UI::MenubarComponent` (`with_menu`), never standalone.
  class MenubarMenuComponent < ApplicationComponent
    # Submenu items — identical model to dropdown_menu (menuitem button/anchor, disabled,
    # separator, href; caller data:/class: merge without clobbering wiring; el splats last).
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

    # Bar-item button (also the submenu's `menu` trigger). `aria-expanded:` highlights it
    # while its submenu is open. Focus-visible ring; disabled-safe.
    TRIGGER = "flex cursor-pointer select-none items-center rounded-sm px-3 py-1.5 text-sm " \
              "font-medium outline-none " \
              "hover:bg-surface-sunken hover:text-text-heading " \
              "focus-visible:bg-surface-sunken focus-visible:text-text-heading " \
              "aria-expanded:bg-surface-sunken aria-expanded:text-text-heading " \
              "aria-disabled:opacity-60 aria-disabled:cursor-not-allowed aria-disabled:pointer-events-none"

    # Submenu panel — CSS anchor positioning (bottom_start, below the bar item, start-aligned,
    # flip-to-stay-on-screen), the same shape as dropdown_menu's bottom_start placement.
    # rubocop:disable Layout/LineLength
    PANEL = "z-50 min-w-[12rem] overflow-hidden rounded-md border border-border bg-surface-overlay p-1 text-text-body shadow-md outline-none mt-1 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_span-right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:left-0"
    # rubocop:enable Layout/LineLength

    # Submenu item — identical to dropdown_menu's ITEM (focus-visible highlight + aria-disabled
    # treatment + SVG normalisation).
    ITEM = "relative flex w-full cursor-pointer select-none items-center gap-2 rounded-sm " \
           "px-2 py-1.5 text-sm outline-none " \
           "hover:bg-surface-sunken hover:text-text-heading " \
           "focus-visible:bg-surface-sunken focus-visible:text-text-heading " \
           "aria-disabled:pointer-events-none aria-disabled:opacity-60 aria-disabled:cursor-not-allowed " \
           "[&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4 " \
           "[&_svg:not([class*='text-'])]:text-text-muted"
    SEPARATOR = "-mx-1 my-1 h-px bg-border"

    # label: the bar item's visible text + accessible name.
    # id:    submenu id (auto-generated; → aria-controls + anchor name).
    def initialize(label:, id: nil, **html_attrs)
      @label = label
      @id = id || "menubar-menu-#{SecureRandom.hex(4)}"
      @trigger_id = "#{@id}-trigger"
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      caller_data = @html_attrs.delete(:data) || {}
      content_tag(:div, safe_join([ trigger_button, submenu_panel ]),
        class: cn("relative", @extra_class),
        # closeOnClickOutside gives the band its mutual exclusion: clicking another bar item
        # is "outside" this wrapper, so this submenu closes as the other opens (matches
        # dropdown_menu/context_menu; the keyboard ←/→-follow path closes explicitly instead).
        data: {
          controller: "menu",
          menubar_item: "",
          action: "click@document->menu#closeOnClickOutside"
        }.merge(caller_data),
        **@html_attrs)
    end

    private

    def trigger_button
      content_tag(:button, @label,
        type: "button",
        id: @trigger_id,
        role: "menuitem",
        tabindex: "-1",
        "aria-haspopup": "menu",
        "aria-expanded": "false",
        "aria-controls": @id,
        style: "anchor-name: --#{@id}",
        data: {
          menu_target: "trigger",
          menubar_target: "item",
          action: "click->menu#toggle keydown->menu#triggerKeydown"
        },
        class: TRIGGER)
    end

    def submenu_panel
      content_tag(:div, safe_join(items),
        id: @id,
        role: "menu",
        "aria-labelledby": @trigger_id,
        tabindex: "-1",
        hidden: true,
        style: "position-anchor: --#{@id}",
        data: { menu_target: "menu", action: "keydown->menu#navigate" },
        class: PANEL)
    end
  end
end
