# frozen_string_literal: true

module UI
  # # BottomNav
  #
  # A fixed mobile bottom navigation bar (a `<nav>` landmark) — a row of icon+label
  # destinations pinned to the bottom of the viewport.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named `<nav>` landmark (i18n default "Bottom navigation",
  #   override via `label:`), the AAA `focus-ring` on every item, and
  #   `aria-current="page"` on the active item.
  # - **You supply:** `items:` (`[{ label:, href:, active: (optional),
  #   icon: (optional HTML string) }]`).
  class BottomNavComponent < ApplicationComponent
    BASE = "fixed bottom-0 left-0 z-50 w-full border-t border-border bg-surface-raised"

    ITEM = "flex flex-col items-center justify-center gap-1 px-4 py-2 text-xs " \
           "font-medium transition-colors focus-ring"

    # items: [{ label:, href:, active: (optional), icon: (optional HTML string) }]
    # label: accessible name for the <nav> landmark (i18n default "Bottom navigation").
    def initialize(items: [], label: nil, **html_attrs)
      @items = items
      @label = label
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:nav,
        class: cn(BASE, @extra_class),
        "aria-label": nav_label,
        **@html_attrs) do
        content_tag(:div, class: "mx-auto flex h-16 max-w-lg items-center justify-around") do
          safe_join(@items.map { |item| nav_item(item) })
        end
      end
    end

    private

    # Resolved at RENDER time (view context exists here, not in initialize).
    def nav_label
      @label || I18n.t("modelrails_ui.bottom_nav.nav_label", default: "Bottom navigation")
    end

    def nav_item(item)
      active = item[:active]
      content_tag(:a,
        href: item[:href],
        class: cn(
          ITEM,
          active ? "text-interactive" : "text-text-muted hover:text-text-heading"
        ),
        "aria-current": (active ? "page" : nil)) do
        concat raw(item[:icon]) if item[:icon]
        concat content_tag(:span, item[:label])
      end
    end
  end
end
