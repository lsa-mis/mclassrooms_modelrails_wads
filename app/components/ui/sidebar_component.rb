# frozen_string_literal: true

module UI
  class SidebarComponent < ApplicationComponent
    # Collapsible application sidebar with nav groups.
    #
    # Usage:
    #   ui :sidebar do |s|
    #     s.with_group(label: "Main") do |g|
    #       g.with_item(label: "Dashboard", href: "/", icon: :home, active: true)
    #       g.with_item(label: "Settings",  href: "/settings", icon: :settings)
    #     end
    #   end

    RAIL_CLS = "group peer fixed inset-y-0 left-0 z-30 flex h-full flex-col " \
               "border-r border-border bg-surface-raised transition-[width] duration-300 " \
               "data-[collapsed=true]:w-16 data-[collapsed=false]:w-64"

    HEADER_CLS = "flex h-14 items-center justify-between border-b border-border px-4"

    TOGGLE_CLS = "inline-flex size-11 shrink-0 items-center justify-center rounded-md " \
                 "text-text-muted hover:bg-surface-sunken hover:text-text-heading " \
                 "focus-ring transition"

    NAV_CLS = "flex-1 overflow-y-auto px-2 py-3"

    GROUP_LABEL = "mb-1 px-3 text-xs font-medium uppercase tracking-wide text-text-muted " \
                  "transition-opacity group-data-[collapsed=true]:opacity-0 group-data-[collapsed=true]:h-0 " \
                  "group-data-[collapsed=true]:overflow-hidden group-data-[collapsed=true]:mb-0"

    ITEM_CLS = "group/item flex min-h-11 items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors " \
               "overflow-hidden " \
               "group-data-[collapsed=true]:justify-center group-data-[collapsed=true]:gap-0 " \
               "hover:bg-surface-sunken hover:text-text-heading " \
               "aria-[current]:bg-surface-sunken aria-[current]:text-text-heading aria-[current]:font-semibold " \
               "focus-ring"

    # The collapsed rail's icon hint. Only a visual affordance: the item's label is clipped
    # to width 0 but stays in the accessibility tree, so the link already has its name —
    # announcing this too would name every item twice. Hence aria-hidden.
    #
    # It must be `fixed` on the modern path: the nav is `overflow-y-auto`, which makes its
    # overflow-x non-visible too, so an `absolute` bubble is clipped at the 64px rail edge.
    # Anchor positioning tethers the fixed bubble back to its item. Pre-Baseline browsers
    # take the `absolute` fallback and lose the hint to that clip — the accessible name is
    # unaffected, so this degrades a nicety, not the semantics.
    RAIL_TOOLTIP = "pointer-events-none z-50 w-max max-w-48 rounded-md px-2 py-1 " \
                   "bg-text-heading text-surface-raised text-xs whitespace-nowrap " \
                   "opacity-0 transition-opacity duration-150 " \
                   "group-hover/item:opacity-100 group-focus-within/item:opacity-100 " \
                   "hidden group-data-[collapsed=true]:block " \
                   "ml-2 supports-[position-area:bottom]:fixed " \
                   "supports-[position-area:bottom]:[position-area:center_right] " \
                   "supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] " \
                   "not-supports-[position-area:bottom]:absolute " \
                   "not-supports-[position-area:bottom]:left-full " \
                   "not-supports-[position-area:bottom]:top-1/2 " \
                   "not-supports-[position-area:bottom]:-translate-y-1/2"

    ITEM_LABEL = "transition-[opacity,width] group-data-[collapsed=true]:w-0 " \
                 "group-data-[collapsed=true]:opacity-0 group-data-[collapsed=true]:overflow-hidden " \
                 "whitespace-nowrap"

    renders_many :groups, "UI::SidebarComponent::GroupComponent"
    renders_many :items,  "UI::SidebarComponent::ItemComponent"

    # brand:     text shown in the header
    # collapsed: initial collapsed state (default: false)
    # label:     accessible name for the <nav> landmark (default: i18n "Sidebar")
    # brand:     text shown in the header
    # collapsed: initial collapsed state. Pass `sidebar_collapsed?` to honour the
    #            visitor's remembered choice on the server and avoid a collapse flash.
    # remember:  persist the choice to a cookie the server can read back (default true)
    # label:     accessible name for the <nav> landmark
    def initialize(brand: nil, collapsed: false, remember: true, label: nil, id: nil, **html_attrs)
      @brand       = brand
      @collapsed   = collapsed
      @remember    = remember
      @id          = id || "sidebar-#{SecureRandom.hex(4)}"
      @label       = label
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:aside,
        class: cn(RAIL_CLS, @extra_class),
        "data-collapsed": @collapsed.to_s,
        data: { controller: "sidebar", sidebar_remember_value: @remember.to_s },
        **@html_attrs) do
        concat header
        concat nav_body
      end
    end

    private

    def header
      content_tag(:div, class: HEADER_CLS) do
        concat content_tag(:span, @brand,
          class: "truncate font-semibold group-data-[collapsed=true]:hidden") if @brand
        concat toggle_btn
      end
    end

    def toggle_btn
      content_tag(:button, type: "button",
        class: TOGGLE_CLS,
        "aria-label": I18n.t("modelrails_ui.sidebar.toggle", default: "Toggle sidebar"),
        "aria-expanded": (!@collapsed).to_s,
        "aria-controls": nav_id,
        data: { sidebar_target: "toggle", action: "click->sidebar#toggle" }) { chevron_icon }
    end

    def nav_body
      content_tag(:nav, id: nav_id, class: NAV_CLS,
        "aria-label": @label || I18n.t("modelrails_ui.sidebar.nav_label", default: "Sidebar")) do
        concat safe_join(groups) if groups.any?
        concat content_tag(:div, safe_join(items), class: "space-y-0.5") if items.any?
        concat content if content?
      end
    end

    def nav_id = "#{@id}-nav"

    def chevron_icon
      content_tag(:svg,
        content_tag(:path, nil, d: "m15 18-6-6 6-6", "stroke-linecap": "round", "stroke-linejoin": "round"),
        xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24",
        fill: "none", stroke: "currentColor", "stroke-width": "2",
        class: "size-4 transition-transform group-data-[collapsed=true]:rotate-180",
        "aria-hidden": "true")
    end

    class GroupComponent < ApplicationComponent
      renders_many :items, "UI::SidebarComponent::ItemComponent"

      def initialize(label: nil, **html_attrs)
        @label      = label
        @html_attrs = html_attrs
      end

      def call
        content_tag(:div, class: "mb-4", **@html_attrs) do
          concat content_tag(:p, @label, class: SidebarComponent::GROUP_LABEL) if @label
          concat content_tag(:div, safe_join(items), class: "space-y-0.5")
          concat content if content?
        end
      end
    end

    class ItemComponent < ApplicationComponent
      ICONS = {
        home:        "M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z M9 22V12h6v10",
        dashboard:   "M3 3h7v9H3z M14 3h7v5h-7z M14 12h7v9h-7z M3 16h7v6H3z",
        folder:      "M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z",
        tasks:       "M9 11l3 3L22 4 M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11",
        settings:    "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z",
        users:       "M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2 M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z M23 21v-2a4 4 0 0 0-3-3.87 M16 3.13a4 4 0 0 1 0 7.75",
        chart:       "M18 20V10 M12 20V4 M6 20v-6",
        mail:        "M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z M22 6l-10 7L2 6",
        bell:        "M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9 M13.73 21a2 2 0 0 1-3.46 0",
        credit_card: "M1 4h22v16H1z M1 10h22",
        logout:      "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4 M16 17l5-5-5-5 M21 12H9"
      }.freeze

      def initialize(label:, href: "#", active: false, icon: nil, **html_attrs)
        @anchor     = "--sb-item-#{SecureRandom.hex(4)}"
        @label      = label
        @href       = href
        @active     = active
        @icon       = icon
        @html_attrs = html_attrs
      end

      def call
        content_tag(:a,
          href: @href,
          class: SidebarComponent::ITEM_CLS,
          style: "anchor-name: #{@anchor}",
          "aria-current": (@active ? "page" : nil),
          **@html_attrs) do
          concat icon_or_fallback
          concat content_tag(:span, @label, class: SidebarComponent::ITEM_LABEL)
          concat rail_tooltip
        end
      end

      private

      def rail_tooltip
        content_tag(:span, @label,
          class: SidebarComponent::RAIL_TOOLTIP,
          style: "position-anchor: #{@anchor}",
          data: { slot: "rail-tooltip" },
          "aria-hidden": "true")
      end

      def icon_or_fallback
        path = @icon && ICONS[@icon.to_sym]
        if path
          content_tag(:svg,
            content_tag(:path, nil, d: path, "stroke-linecap": "round", "stroke-linejoin": "round"),
            xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24",
            fill: "none", stroke: "currentColor", "stroke-width": "2",
            class: "size-4 shrink-0",
            "aria-hidden": "true")
        else
          content_tag(:span, @label[0],
            class: "hidden size-5 shrink-0 items-center justify-center rounded text-xs font-semibold group-data-[collapsed=true]:flex",
            "aria-hidden": "true")
        end
      end
    end
  end
end
