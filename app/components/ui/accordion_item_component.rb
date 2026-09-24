# frozen_string_literal: true

module UI
  # A single accordion row, rendered as a native <details>/<summary> disclosure.
  # Usage, options and the accessibility contract: docs/components/accordion.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class AccordionItemComponent < ApplicationComponent
    SUMMARY_CLASSES = "flex flex-1 items-start justify-between gap-4 rounded-md py-4 text-left text-sm font-medium " \
                      "cursor-pointer list-none [&::-webkit-details-marker]:hidden hover:underline focus-ring"

    def initialize(title:, open: false, **html_attrs)
      @title = title
      @open = open
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:details, details_content, **details_attrs)
    end

    private

    def details_attrs
      attrs = @html_attrs.merge(class: cn("border-b last:border-b-0 group", @extra_class))
      attrs[:open] = true if @open
      attrs
    end

    def details_content
      safe_join([
        content_tag(:summary, summary_content, class: SUMMARY_CLASSES),
        content_tag(:div, content, class: "pb-4 pt-0 text-sm")
      ])
    end

    def summary_content
      safe_join([
        @title,
        content_tag(:svg, content_tag(:path, nil, d: "m6 9 6 6 6-6"),
          xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24",
          fill: "none", stroke: "currentColor", "stroke-width": "2",
          "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true",
          class: "pointer-events-none size-4 shrink-0 translate-y-0.5 text-text-muted transition-transform duration-200 group-open:rotate-180")
      ])
    end
  end
end
