# frozen_string_literal: true

module UI
  # CSS-only collapse via a native <details>/<summary> disclosure.
  #
  # trigger slot: content for the summary row (button, icon, label, etc.)
  # open:         render pre-expanded (default: false)
  #
  # Accessibility contract:
  # - Native <details>/<summary> carries the disclosure semantics — the summary is
  #   focusable and toggles on Enter/Space, and the browser manages aria-expanded.
  # - The summary owns the AAA focus indicator via `focus-ring` (an offset outline,
  #   never a box-shadow ring: a ring is clipped by overflow-hidden ancestors and
  #   vanishes in forced-colors mode — a 2.4.7 failure).
  # - The native webkit disclosure marker is hidden so caller-supplied trigger markup
  #   owns the open/closed affordance.
  class CollapsibleComponent < ApplicationComponent
    SUMMARY_CLS = "flex min-h-11 cursor-pointer list-none items-center justify-between gap-2 " \
                  "[&::-webkit-details-marker]:hidden focus-ring"
    CONTENT_CLS = "mt-2"

    renders_one :trigger

    def initialize(open: false, **html_attrs)
      @open = open
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      attrs = { class: cn(@extra_class), **@html_attrs }
      attrs[:open] = true if @open

      content_tag(:details, **attrs) do
        concat content_tag(:summary, trigger, class: SUMMARY_CLS)
        concat content_tag(:div, content, class: CONTENT_CLS)
      end
    end
  end
end
