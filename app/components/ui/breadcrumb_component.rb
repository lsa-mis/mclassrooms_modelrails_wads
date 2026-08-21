# frozen_string_literal: true

module UI
  # # Breadcrumb
  #
  # A breadcrumb trail (`<nav aria-label>` + ordered list). The last item is the current page
  # (`aria-current="page"`, not a link); earlier items are links separated by a decorative
  # (`aria-hidden`) separator.
  #
  # ## Accessibility contract
  # - **Guarantees:** `<nav>` named by `label:` (i18n, default "Breadcrumb"); an `<ol>` of crumbs;
  #   the current page is `aria-current="page"` and not a link; separators are `aria-hidden`;
  #   links get a visible `:focus-visible` ring.
  # - **You supply:** `items:` (`[{ label:, href: }, …, { label: }]` — the LAST item, with no
  #   `href`, is the current page).
  class BreadcrumbComponent < ApplicationComponent
    # inline-flex + min-h-11: 44px AAA target floor (2.5.5) — text-sm crumb
    # links measured ~20px tall (2026-07-13 gate upgrade, backlog #10). The
    # hit area grows; the text baseline is unchanged.
    LINK = "inline-flex min-h-11 min-w-11 items-center rounded-sm text-text-muted transition-colors " \
           "hover:text-text-heading " \
           "focus-ring focus-visible:text-text-heading"
    CURRENT = "font-medium text-text-heading"

    # items: [{ label:, href: }, ..., { label: }] — last item is the current page (no href).
    # separator: the visual divider between crumbs (decorative). label: the <nav> accessible
    # name (i18n; default t("ui.breadcrumb.label", default: "Breadcrumb")).
    def initialize(items: [], separator: "/", label: nil, max_items: nil, **html_attrs)
      if max_items && max_items < 2
        raise ArgumentError, "UI::Breadcrumb max_items must be at least 2 (got #{max_items.inspect})"
      end

      @max_items = max_items
      @items = items
      @separator = separator
      @label = label
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:nav, ordered_list, "aria-label": nav_label, **@html_attrs)
    end

    private

    # t() is resolved at RENDER time (not in initialize — no view context there).
    def nav_label
      @label || t("ui.breadcrumb.label", default: "Breadcrumb")
    end

    # Collapse the middle when the trail is longer than `max_items`: keep the root and
    # the tail, and stand one ellipsis in for what was dropped. The collapsed crumbs are
    # removed for EVERYONE — no visually-hidden copy — so the rendered trail never claims
    # a depth the reader cannot reach.
    def displayed
      return @items unless @max_items && @items.size > @max_items

      tail = @items.last(@max_items - 1)
      [ @items.first, :ellipsis, *tail ]
    end

    def ordered_list
      shown = displayed
      content_tag(:ol,
        safe_join(shown.each_with_index.map { |item, i|
          item == :ellipsis ? ellipsis : crumb(item, i == shown.size - 1)
        }),
        class: cn("flex flex-wrap items-center gap-1.5 break-words text-sm text-text-muted sm:gap-2.5", @extra_class))
    end

    def ellipsis
      content_tag(:li, class: "inline-flex items-center gap-1.5") do
        safe_join([
          content_tag(:span, "…",
            class: "select-none px-1 text-text-muted",
            "aria-hidden": "true",
            data: { slot: "breadcrumb-ellipsis" }),
          content_tag(:span, @separator, class: "select-none text-text-muted", "aria-hidden": "true")
        ])
      end
    end

    def crumb(item, is_last)
      content_tag(:li, class: "inline-flex items-center gap-1.5") do
        if is_last
          content_tag(:span, item[:label], class: CURRENT, "aria-current": "page")
        else
          safe_join([
            # href-less items render as plain text — "linked for some viewers,
            # plain for others" (e.g. a hidden building crumb) is expressible.
            (item[:href].present? ? content_tag(:a, item[:label], href: item[:href], class: LINK) : content_tag(:span, item[:label], class: "text-text-muted")),
            content_tag(:span, @separator, class: "select-none text-text-muted", "aria-hidden": "true")
          ])
        end
      end
    end
  end
end
