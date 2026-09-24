# frozen_string_literal: true

module UI
  # CSS-only collapse via a native <details>/<summary> disclosure.
  # Usage, options and the accessibility contract: docs/components/collapsible.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class CollapsibleComponent < ApplicationComponent
    SUMMARY_CLS = "flex min-h-input cursor-pointer list-none items-center justify-between gap-2 " \
                  "[&::-webkit-details-marker]:hidden focus-ring"
    CONTENT_CLS = "mt-2"

    renders_one :trigger

    def initialize(open: false, disabled: false, **html_attrs)
      @open = open
      @disabled = disabled
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      attrs = { class: cn(@extra_class), **@html_attrs }
      attrs[:open] = true if @open

      content_tag(:details, **attrs) do
        concat content_tag(:summary, trigger, **summary_attrs)
        concat content_tag(:div, content, class: CONTENT_CLS)
      end
    end

    private

    def summary_attrs
      return { class: SUMMARY_CLS } unless @disabled

      {
        class: cn(SUMMARY_CLS, "pointer-events-none opacity-60"),
        "aria-disabled": "true",
        tabindex: "-1"
      }
    end
  end
end
