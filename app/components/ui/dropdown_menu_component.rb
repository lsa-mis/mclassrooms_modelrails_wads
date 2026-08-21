# frozen_string_literal: true

module UI
  # # Dropdown menu
  #
  # A button that opens a menu of actions, implementing the WAI-ARIA APG menu-button
  # pattern via the `menu` Stimulus controller shipped alongside this component.
  # Placement is CSS anchor positioning: the panel is `position: fixed` (so its
  # containing block is the viewport), tethered to the trigger via `anchor-name`/
  # `position-anchor`; `position-area` places it and `position-try-fallbacks` keeps it
  # on-screen. The controller owns open/close and the keyboard model (roving tabindex,
  # type-ahead, Escape/Tab/outside-click dismissal with focus restoration).
  #
  # ## Use when
  # - A trigger opens a list of *commands/actions* (Edit, Duplicate, Delete…).
  #
  # ## Don't use when
  # - You need *selection from a list* of values — use a listbox/`select`.
  # - The content is a non-menu overlay (a form, rich detail) — use `popover`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<button>` trigger with `aria-haspopup="menu"`,
  #   `aria-expanded` (kept in sync) and `aria-controls`; a `role="menu"` panel named by
  #   the trigger (`aria-labelledby`); items are `role="menuitem"` with roving tabindex;
  #   keyboard nav (↑/↓ wrap skipping disabled, Home/End, type-ahead, Enter/Space
  #   activate, Escape/Tab/outside-click close) with focus restored to the trigger.
  # - **You supply:** a `with_trigger` slot (the button's visible label) and one or more
  #   `with_item` slots. Icon-only triggers MUST pass `aria_label:` (the 0b axe proves
  #   the accessible name).
  class DropdownMenuComponent < ApplicationComponent
    renders_one :trigger

    # Each item is a real menuitem button (or an anchor when `href:` is given).
    # `disabled:` marks it `aria-disabled` (skipped by keyboard nav; activation
    # rejected). `separator: true` renders a non-interactive divider in source order
    # instead of an item. Pass-through `class:`/attrs land on the element.
    renders_many :items, ->(separator: false, disabled: false, href: nil, checkbox: false,
      radio: nil, value: nil, checked: false, tone: nil, submenu: nil, **attrs, &block) do
      next content_tag(:div, "", role: "separator", class: SEPARATOR) if separator
      next submenu_group(submenu, disabled: disabled, **attrs, &block) if submenu

      tone = validate_tone(tone)
      tag_name = href ? :a : :button
      caller_data = attrs.delete(:data) || {}
      # menuitemcheckbox / menuitemradio per the APG menu pattern. `aria-checked` is
      # rendered from server state so the menu reads correctly before any JS runs;
      # `menu#activate` then toggles it in place rather than closing the menu.
      role = if radio
        "menuitemradio"
      else
        (checkbox ? "menuitemcheckbox" : "menuitem")
      end
      wiring = { menu_target: "item", action: "click->menu#activate" }
      wiring[:menu_radio_group] = radio if radio
      wiring[:menu_value] = value if value
      wiring[:tone] = tone if tone
      el = {
        role: role,
        tabindex: "-1",
        class: cn(ITEM, (ITEM_TONES.fetch(tone) if tone), attrs.delete(:class)),
        data: wiring.merge(caller_data)
      }
      el[:"aria-checked"] = checked.to_s if role != "menuitem"
      el[:href] = href if href
      el[:type] = "button" unless href
      el[:"aria-disabled"] = "true" if disabled
      # `el` splats LAST so the ARIA/Stimulus wiring (role/tabindex/class/data) always wins
      # over caller attrs — callers may add attrs but cannot break the menu contract.
      content_tag(tag_name, capture(&block), **attrs, **el)
    end

    PANEL_BASE = "z-50 min-w-[8rem] overflow-hidden rounded-md border border-border " \
                 "bg-surface-overlay p-1 text-text-body shadow-md outline-none"

    # Menu item: focus-visible AND hover share the same highlight (roving focus must be
    # visible — no bare outline-none). Disabled items are inert + de-emphasised on
    # semantic tokens. SVG sizing/colour normalised. AAA contrast of the focus highlight
    # is adjudicated by the app 0b CI axe (the 7:1 hook is CI-only), not locally.
    ITEM = "relative flex w-full cursor-pointer select-none items-center gap-2 rounded-sm " \
           "px-2 py-1.5 text-sm outline-none " \
           "hover:bg-surface-sunken hover:text-text-heading " \
           "focus-visible:bg-surface-sunken focus-visible:text-text-heading " \
           "aria-disabled:pointer-events-none aria-disabled:opacity-60 aria-disabled:cursor-not-allowed " \
           "[&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4 " \
           "[&_svg:not([class*='text-'])]:text-text-muted"
    SEPARATOR = "-mx-1 my-1 h-px bg-border"

    # Opens to the side of its parent item, flipping to the other side near the edge.
    SUBMENU_PLACEMENT = "supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:right_span-bottom] supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:left-full not-supports-[position-area:bottom]:top-0"

    # Signal tones are TEXT colours, never a fill — a menu item keeps the surface
    # highlight it shares with every other item and only its label changes colour.
    ITEM_TONES = {
      danger: "text-danger hover:text-danger focus-visible:text-danger"
    }.freeze

    # Collects a submenu's items so the caller writes the same `with_item` it uses on the
    # parent, in source order:
    #
    #   c.with_item(submenu: "Share") { |sub| sub.with_item { "Email" } }
    class SubmenuBuilder
      attr_reader :items

      def initialize(component)
        @component = component
        @items = []
      end

      def with_item(**opts, &block)
        @items << @component.submenu_item(**opts, &block)
        nil
      end
    end

    # A submenu is a nested controller with a DISTINCT identifier, so the sub-trigger can
    # be `data-menu-target="item"` (staying in the parent's arrow-key rotation) while also
    # being `data-submenu-target="trigger"`. One element, two controllers, no collision.
    def submenu_group(label, disabled: false, **attrs, &block)
      builder = SubmenuBuilder.new(self)
      capture(builder, &block)
      id = "submenu-#{SecureRandom.hex(4)}"

      content_tag(:div,
        data: {
          controller: "submenu",
          action: "mouseleave->submenu#scheduleClose menu:close->submenu#forceClose"
        },
        style: "anchor-name: --#{id}") do
        safe_join([ submenu_trigger(label, id, disabled, **attrs), submenu_panel(id, builder.items) ])
      end
    end

    def submenu_trigger(label, id, disabled, **attrs)
      el = {
        type: "button",
        role: "menuitem",
        tabindex: "-1",
        "aria-haspopup": "menu",
        "aria-expanded": "false",
        "aria-controls": id,
        class: cn(ITEM, "justify-between", attrs.delete(:class)),
        data: {
          menu_target: "item",
          submenu_target: "trigger",
          action: "click->submenu#toggle keydown->submenu#triggerKeydown mouseenter->submenu#open"
        }
      }
      el[:"aria-disabled"] = "true" if disabled
      content_tag(:button, safe_join([ label, submenu_chevron ]), **attrs, **el)
    end

    def submenu_panel(id, items)
      content_tag(:div, safe_join(items),
        id: id,
        role: "menu",
        tabindex: "-1",
        hidden: true,
        style: "position-anchor: --#{id}",
        data: { submenu_target: "panel", action: "keydown->submenu#navigate" },
        class: cn(PANEL_BASE, SUBMENU_PLACEMENT))
    end

    def submenu_chevron
      content_tag(:svg, tag.path(d: "m9 18 6-6-6-6"),
        class: "size-4 shrink-0 text-text-muted", viewBox: "0 0 24 24", fill: "none",
        stroke: "currentColor", "stroke-width": "2", "aria-hidden": "true")
    end

    # Rendered by SubmenuBuilder, so it carries `data-submenu-target` rather than
    # `data-menu-target` — sub-items belong to the submenu's rotation, not the parent's.
    def submenu_item(disabled: false, href: nil, **attrs, &block)
      tag_name = href ? :a : :button
      el = {
        role: "menuitem",
        tabindex: "-1",
        class: cn(ITEM, attrs.delete(:class)),
        data: { submenu_target: "item", action: "click->submenu#activate" }
      }
      el[:href] = href if href
      el[:type] = "button" unless href
      el[:"aria-disabled"] = "true" if disabled
      content_tag(tag_name, capture(&block), **attrs, **el)
    end

    def validate_tone(tone)
      return nil if tone.nil?

      key = tone.to_sym
      return key if ITEM_TONES.key?(key)

      raise ArgumentError,
        "UI::DropdownMenu unknown item tone: #{tone.inspect} (allowed: #{ITEM_TONES.keys.join(", ")})"
    end

    SIDES = %i[bottom top].freeze
    ALIGNS = %i[start end].freeze

    # Anchor-positioning placement — `side` (bottom/top) × `align` (start/end). Each value
    # carries the gap margin, the modern path (supports-[position-area]: `fixed` + a
    # `position-area` cell + `position-try-fallbacks: flip-block` to stay on-screen) and
    # the pre-Baseline `absolute` fallback offsets. `span-right`/`span-left` edge-align the
    # menu to the trigger (unlike a tooltip, which centres). One line per placement.
    # rubocop:disable Layout/LineLength
    PLACEMENTS = {
      bottom_start: "mt-1 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_span-right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:left-0",
      bottom_end: "mt-1 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_span-left] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:right-0",
      top_start: "mb-1 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:top_span-right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:bottom-full not-supports-[position-area:bottom]:left-0",
      top_end: "mb-1 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:top_span-left] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:bottom-full not-supports-[position-area:bottom]:right-0"
    }.freeze
    # rubocop:enable Layout/LineLength

    # side:          :bottom | :top
    # align:         :start | :end (edge-aligned to the trigger)
    # id:            menu id (auto-generated if omitted; → aria-controls + anchor name)
    # aria_label:    trigger accessible name (REQUIRED for icon-only triggers)
    # trigger_class: CSS for the trigger button (default canonical .btn-secondary)
    def initialize(side: :bottom, align: :start, id: nil, aria_label: nil,
      trigger_class: "btn-secondary", **html_attrs)
      @id = id || "menu-#{SecureRandom.hex(4)}"
      @trigger_id = "#{@id}-trigger"
      @side = validate(:side, side, SIDES)
      @align = validate(:align, align, ALIGNS)
      @aria_label = aria_label
      @trigger_class = trigger_class
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      raise ArgumentError, "UI::DropdownMenuComponent requires a with_trigger slot" unless trigger?

      content_tag(:div, **wrapper_attrs) do
        safe_join([ trigger_button, menu_panel ])
      end
    end

    private

    def wrapper_attrs
      caller_data = @html_attrs.delete(:data) || {}
      caller_style = @html_attrs.delete(:style)
      {
        class: cn("relative inline-block", @extra_class),
        style: [ "anchor-name: --#{@id}", caller_style ].compact.join("; "),
        data: { controller: "menu", action: "click@document->menu#closeOnClickOutside" }.merge(caller_data)
      }.merge(@html_attrs)
    end

    def trigger_button
      content_tag(:button, trigger,
        type: "button",
        id: @trigger_id,
        "aria-haspopup": "menu",
        "aria-expanded": "false",
        "aria-controls": @id,
        "aria-label": @aria_label,
        data: { menu_target: "trigger", action: "click->menu#toggle keydown->menu#triggerKeydown" },
        class: @trigger_class)
    end

    def menu_panel
      content_tag(:div, safe_join(items),
        id: @id,
        role: "menu",
        "aria-labelledby": @trigger_id,
        tabindex: "-1",
        hidden: true,
        style: "position-anchor: --#{@id}",
        data: { menu_target: "menu", action: "keydown->menu#navigate" },
        class: cn(PANEL_BASE, PLACEMENTS.fetch(:"#{@side}_#{@align}")))
    end

    def validate(name, value, allowed)
      key = value.to_sym
      return key if allowed.include?(key)

      raise ArgumentError,
        "UI::DropdownMenu unknown #{name}: #{value.inspect} (allowed: #{allowed.join(", ")})"
    end
  end
end
