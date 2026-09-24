# frozen_string_literal: true

module UI
  # The form-level error panel — and the ANNOUNCEMENT MECHANISM for failed submits.
  # Usage, options and the accessibility contract: docs/components/error_summary.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
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
      content_tag(:div, tabindex: "-1", autofocus: true, data: { slot: "error-summary" },
                       class: cn(BASE, @extra_class), **@html_attrs) do
        content_tag(:div, role: "alert", class: "flex items-start gap-3") do
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
          # A list item alone (not in-text) — 2.5.5 AAA applies. min-h-input
          # meets the 44px floor, which covers axe's 24px AA target-size
          # rule and its neighbor-spacing check too. It resolves through
          # --form-input-height, so a fork retuning that knob moves this with
          # every other control rather than leaving it behind.
          content_tag(:a, item[:message], href: item[:href],
            class: "inline-flex min-h-input items-center underline focus-ring")
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
