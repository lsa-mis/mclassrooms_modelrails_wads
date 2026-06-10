# frozen_string_literal: true

module UI
  # # Navigation menu
  #
  # A horizontal site-navigation bar (the WAI-ARIA APG **navigation-menu**, i.e. a
  # `<nav>` of links where some entries open a **disclosure** flyout — NOT a
  # `role="menu"` widget). Each flyout trigger is a real `<button>` whose
  # `aria-expanded` is kept in sync (and `aria-controls` points at its panel) by the
  # component-owned `navigation-menu` Stimulus controller; the panel is hover/click
  # managed with outside-click dismissal.
  #
  # ## Use when
  # - Top-level site navigation where some sections reveal a small set of links.
  #
  # ## Don't use when
  # - You need a *command/action menu* (Edit, Delete…) — use `dropdown_menu`.
  # - You need an application rail with grouped sections — use `sidebar`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a **named** `<nav>` landmark (i18n default, override via `label:`);
  #   flyout triggers are real `<button>`s carrying `aria-expanded` (synced) +
  #   `aria-controls` → their `id`'d panel (the disclosure pattern); the AAA offset
  #   `focus-ring` on every trigger, link and panel link; `aria-current="page"` on the
  #   active link; the chevron is decorative (`aria-hidden`).
  # - **You supply:** items (label, optional href, optional active) and — for flyout
  #   items — the panel links via the slot block.
  class NavigationMenuComponent < ApplicationComponent
    ROOT = "relative flex max-w-max flex-1 items-center"

    # List justification keyed off the `align:` enum (fail-loud guarded).
    JUSTIFY = {
      start: "justify-start",
      center: "justify-center",
      end: "justify-end"
    }.freeze

    LIST = "flex flex-1 list-none items-center gap-1"

    # Trigger button style (item with flyout content)
    TRIGGER = "group inline-flex h-9 w-max items-center justify-center rounded-md bg-surface-raised " \
              "px-4 py-2 text-sm font-medium transition-[color,box-shadow] focus-ring " \
              "hover:bg-surface-sunken hover:text-text-heading " \
              "disabled:pointer-events-none disabled:opacity-50 " \
              "data-[state=open]:bg-surface-sunken/50 data-[state=open]:text-text-heading"

    # Plain link style (item without flyout)
    LINK_CLS = "inline-flex h-9 w-max items-center justify-center rounded-md bg-surface-raised " \
               "px-4 py-2 text-sm font-medium transition-[color,box-shadow] focus-ring " \
               "hover:bg-surface-sunken hover:text-text-heading " \
               "aria-[current]:bg-surface-sunken/50 aria-[current]:text-text-heading"

    # Flyout panel
    CONTENT = "absolute top-full left-0 z-50 mt-1.5 min-w-48 overflow-hidden rounded-md border " \
              "bg-surface-overlay p-1 text-text-body shadow"

    # Styled link inside a flyout panel
    PANEL_LINK = "flex flex-col gap-1 rounded-sm p-2 text-sm transition-all focus-ring " \
                 "hover:bg-surface-sunken hover:text-text-heading " \
                 "aria-[current]:bg-surface-sunken/50 aria-[current]:text-text-heading"

    CHEVRON_PATH = "m6 9 6 6 6-6"

    renders_many :items, "UI::NavigationMenuComponent::ItemComponent"

    # align: list justification — :start | :center | :end (default :center)
    # label: accessible name for the <nav> landmark (default: i18n "Main")
    def initialize(align: :center, label: nil, **html_attrs)
      @align = validate(:align, align, JUSTIFY.keys)
      @label = label
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:nav,
        class: cn(ROOT, @extra_class),
        "aria-label": @label || I18n.t("modelrails_ui.navigation_menu.nav_label", default: "Main"),
        **@html_attrs) do
        content_tag(:ul, class: cn(LIST, JUSTIFY.fetch(@align))) do
          safe_join(items.map { |item| content_tag(:li, item, class: "relative") })
        end
      end
    end

    private

    def validate(name, value, allowed)
      key = value.to_sym
      return key if allowed.include?(key)

      raise ArgumentError,
        "UI::NavigationMenuComponent unknown #{name}: #{value.inspect} (allowed: #{allowed.join(", ")})"
    end

    public

    # Represents one entry in the navigation bar.
    # href: present  → plain styled link
    # href: absent   → trigger button + flyout (add content via block)
    class ItemComponent < ApplicationComponent
      CHEVRON_PATH = "m6 9 6 6 6-6"

      def initialize(label:, href: nil, active: false, **html_attrs)
        @label = label
        @href = href
        @active = active
        @panel_id = "nav-flyout-#{SecureRandom.hex(4)}"
        @extra_class = html_attrs.delete(:class)
        @html_attrs = html_attrs
      end

      def call
        if @href
          link_item
        else
          trigger_item
        end
      end

      private

      def link_item
        content_tag(:a, @label,
          href: @href,
          class: cn(NavigationMenuComponent::LINK_CLS, @extra_class),
          "aria-current": (@active ? "page" : nil),
          **@html_attrs)
      end

      def trigger_item
        content_tag(:div,
          class: "relative",
          data: {
            controller: "navigation-menu",
            action: "mouseenter->navigation-menu#open mouseleave->navigation-menu#scheduleClose " \
                    "click@document->navigation-menu#closeOnClickOutside"
          }) do
          concat trigger_btn
          concat flyout
        end
      end

      def trigger_btn
        content_tag(:button,
          type: "button",
          class: cn(NavigationMenuComponent::TRIGGER, @extra_class),
          "aria-expanded": "false",
          "aria-haspopup": "true",
          "aria-controls": @panel_id,
          data: { navigation_menu_target: "trigger", state: "closed" },
          **@html_attrs) do
          concat @label
          concat chevron
        end
      end

      def flyout
        content_tag(:div,
          content,
          id: @panel_id,
          class: NavigationMenuComponent::CONTENT,
          hidden: true,
          data: {
            navigation_menu_target: "content",
            action: "mouseenter->navigation-menu#open mouseleave->navigation-menu#scheduleClose"
          })
      end

      def chevron
        content_tag(:svg,
          content_tag(:path, nil, d: CHEVRON_PATH, "stroke-linecap": "round", "stroke-linejoin": "round"),
          xmlns: "http://www.w3.org/2000/svg",
          viewBox: "0 0 24 24",
          fill: "none",
          stroke: "currentColor",
          "stroke-width": "2",
          class: "relative top-[1px] ml-1 size-3 transition-transform duration-200 " \
                 "group-data-[state=open]:rotate-180",
          "aria-hidden": "true")
      end
    end
  end
end
