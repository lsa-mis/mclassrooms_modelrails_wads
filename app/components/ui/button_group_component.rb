# frozen_string_literal: true

module UI
  # Presentational `role="group"` wrapper that segments its children into a single
  # control: it collapses the inner corners and overlaps the borders so adjacent
  # buttons read as one bar. Purely visual — it owns no state, JS, or keyboard
  # behaviour; the children (UI::Button et al.) carry their own a11y contract.
  #
  # `aria_label:` is optional: a group benefits from an accessible name, but a
  # button group is often already labelled by surrounding context, so it is left
  # to the caller rather than required.
  class ButtonGroupComponent < ApplicationComponent
    BASE = "inline-flex rounded-md shadow-sm " \
           "[&>*]:rounded-none " \
           "[&>*:first-child]:rounded-l-md " \
           "[&>*:last-child]:rounded-r-md " \
           "[&>*:not(:first-child)]:-ml-px"

    def initialize(aria_label: nil, **html_attrs)
      @aria_label = aria_label
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, content,
        class: cn(BASE, @extra_class),
        role: "group",
        "aria-label": @aria_label,
        **@html_attrs)
    end
  end
end
