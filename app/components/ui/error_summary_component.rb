# frozen_string_literal: true

module UI
  # # Error Summary
  #
  # The form-level error panel — and the ANNOUNCEMENT MECHANISM for failed
  # submits. `role="alert"` alone does not announce on a server-rendered
  # response (a live region only fires on mutation, and the region arrives
  # with its content), and Turbo's 422 re-render drops focus to <body>. So
  # this container is focusable (`tabindex="-1"`) and carries `autofocus`:
  # browsers honour it on load, Turbo Drive re-honours it after every render.
  # Each item links to its field, turning the summary into a working task list.
  #
  # ## Use when
  # - Rendering `ActiveModel::Errors` at the top of a form. The form builder's
  #   `error_summary` shim builds `items` (with per-field anchors) for you.
  #
  # ## Accessibility contract
  # - **Guarantees:** a focusable, autofocused `role="alert"` container; a
  #   count-pluralized heading at a configurable level (default h2 — pass
  #   `heading_level:` when the form sits under deeper headings, 1.3.1/2.4.10);
  #   items as real links to `#<field_id>` when `href` is given.
  # - **You supply:** `items` — `[{message:, href:}]`; omit `href` for
  #   object-level (`:base`) errors.
  class ErrorSummaryComponent < ApplicationComponent
    BASE = "rounded-lg border border-danger-border bg-danger-surface p-4"

    def initialize(items:, heading_level: 2, **html_attrs)
      @items = items
      @heading_level = Integer(heading_level)
      raise ArgumentError, "heading_level must be 1..6, got #{@heading_level}" unless (1..6).cover?(@heading_level)

      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def render?
      @items.any?
    end

    def call
      content_tag(:div, role: "alert", tabindex: "-1", autofocus: true,
                       class: cn(BASE, @extra_class), **@html_attrs) do
        content_tag(:div, class: "flex items-start gap-3") do
          safe_join([ icon, body ])
        end
      end
    end

    private

    def heading
      text = I18n.t("modelrails_ui.error_summary.heading", count: @items.size,
        default: @items.size == 1 ? "1 error prevented this from being saved" : "%{count} errors prevented this from being saved" % { count: @items.size })
      content_tag(:"h#{@heading_level}", text, class: "text-sm font-semibold text-danger")
    end

    def body
      content_tag(:div) do
        safe_join([ heading, item_list ])
      end
    end

    def item_list
      content_tag(:ul, class: "mt-2 list-disc list-inside text-sm text-danger") do
        safe_join(@items.map { |item| list_item(item) })
      end
    end

    def list_item(item)
      content_tag(:li) do
        if item[:href]
          content_tag(:a, item[:message], href: item[:href], class: "underline focus-ring")
        else
          item[:message]
        end
      end
    end

    # Self-contained: arbitrary hosts have no `icon` helper.
    def icon
      raw(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' \
        'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ' \
        'class="size-5 shrink-0 mt-0.5 text-danger-icon" aria-hidden="true">' \
        '<circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/>' \
        '<line x1="12" y1="16" x2="12.01" y2="16"/></svg>'
      )
    end
  end
end
