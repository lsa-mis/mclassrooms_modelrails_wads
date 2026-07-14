# frozen_string_literal: true

module UI
  # # Navbar
  #
  # A responsive top navigation bar (a `<nav>` landmark) — a brand, inline desktop links, an
  # optional right-aligned action area (block content), and a mobile disclosure: a hamburger
  # toggles a stacked menu panel. The disclosure follows the WAI-ARIA APG disclosure pattern
  # (aria-expanded/controls + Escape + outside-click), driven by the `navbar` Stimulus controller.
  #
  # ## Accessibility contract
  # - **Guarantees:** `<nav>` named by `label:` (i18n default "Main"); the hamburger is a
  #   `<button>` with synced `aria-expanded` + `aria-controls`; the mobile panel toggles
  #   `hidden`; Escape closes it (focus returns to the toggle); an outside click closes it; the
  #   active link carries `aria-current="page"`.
  # - **You supply:** `items:` (`[{ label:, href:, active: }]`); optional `brand:`/`brand_href:`;
  #   optional block content for the right action area.
  # - **Scope:** the action-area block is desktop-only; the mobile menu shows `items:` only.
  class NavbarComponent < ApplicationComponent
    LINK_BASE = "text-sm font-medium transition-colors hover:text-text-heading"
    LINK_IDLE = "text-text-muted"
    LINK_ACTIVE = "text-text-heading"
    MOBILE_LINK = "flex min-h-11 items-center rounded-md px-3 py-2 text-sm font-medium hover:bg-surface-sunken hover:text-text-heading"

    # brand/brand_href: optional brand link. items: nav links. label: the <nav> accessible name
    # (i18n; defaults to t("ui.navbar.label", default: "Main")). Block content → right action area.
    def initialize(brand: nil, brand_href: "/", items: [], label: nil, **html_attrs)
      @brand = brand
      @brand_href = brand_href
      @items = items
      @label = label
      @menu_id = "navbar-menu-#{SecureRandom.hex(4)}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    # rubocop:disable Layout/LineLength
    NAV = "sticky top-0 z-50 w-full border-b bg-surface-raised/95 backdrop-blur supports-[backdrop-filter]:bg-surface-raised/60"
    # rubocop:enable Layout/LineLength

    def call
      caller_data = @html_attrs.delete(:data) || {}
      content_tag(:nav, safe_join([ top_row, mobile_menu ]),
        "aria-label": nav_label,
        class: cn(NAV, @extra_class),
        data: {
          controller: "navbar",
          action: "keydown->navbar#closeOnEscape click@document->navbar#closeOnClickOutside"
        }.merge(caller_data),
        **@html_attrs)
    end

    private

    # t() is resolved at RENDER time (here, not in initialize — no view context there).
    def nav_label
      @label || t("ui.navbar.label", default: "Main")
    end

    def top_row
      content_tag(:div, safe_join([ brand_link, desktop_menu, spacer, action_area, hamburger ]),
        class: "container mx-auto flex h-14 items-center gap-4 px-4")
    end

    def brand_link
      return "" unless @brand

      content_tag(:a, @brand, href: @brand_href,
        class: "mr-2 flex min-h-11 min-w-11 items-center font-semibold text-text-heading")
    end

    def desktop_menu
      return "" if @items.empty?

      content_tag(:div, safe_join(@items.map { |item| nav_link(item) }),
        class: "hidden items-center gap-1 md:flex")
    end

    def nav_link(item)
      content_tag(:a, item[:label], href: item[:href],
        "aria-current": (item[:active] ? "page" : nil),
        class: cn(LINK_BASE, item[:active] ? LINK_ACTIVE : LINK_IDLE))
    end

    def spacer
      content_tag(:div, nil, class: "flex-1")
    end

    # Desktop-only (hidden md:flex). The block CTA is intentionally NOT mirrored into the
    # mobile menu this pass — for mobile parity, put the action in `items:` or extend the
    # mobile panel with a captured slot. (Deliberate scope cut; see the accessibility note.)
    def action_area
      return "" unless content?

      content_tag(:div, content, class: "hidden items-center gap-2 md:flex")
    end

    HAMBURGER_CLASS = "inline-flex min-h-11 min-w-11 items-center justify-center rounded-md p-2 " \
                      "text-text-muted hover:bg-surface-sunken hover:text-text-heading md:hidden"

    def hamburger
      return "" if @items.empty?

      content_tag(:button, hamburger_icon,
        type: "button",
        "aria-label": t("ui.navbar.toggle", default: "Toggle menu"),
        "aria-expanded": "false",
        "aria-controls": @menu_id,
        class: HAMBURGER_CLASS,
        data: { navbar_target: "toggle", action: "click->navbar#toggle" })
    end

    def mobile_menu
      return "" if @items.empty?

      content_tag(:div, safe_join(@items.map { |item| mobile_link(item) }),
        id: @menu_id,
        hidden: true,
        class: "space-y-1 border-t px-4 py-2 md:hidden",
        data: { navbar_target: "menu" })
    end

    def mobile_link(item)
      content_tag(:a, item[:label], href: item[:href],
        "aria-current": (item[:active] ? "page" : nil),
        class: cn(MOBILE_LINK, item[:active] ? LINK_ACTIVE : LINK_IDLE))
    end

    def hamburger_icon
      raw(<<~SVG)
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <line x1="4" x2="20" y1="6" y2="6"/>
          <line x1="4" x2="20" y1="12" y2="12"/>
          <line x1="4" x2="20" y1="18" y2="18"/>
        </svg>
      SVG
    end
  end
end
