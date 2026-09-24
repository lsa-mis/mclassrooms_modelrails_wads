# frozen_string_literal: true

module UI
  # A grouping of related toggle buttons (`ui :toggle`) wired to the `toggle-group` Stimulus controller, which enforces single- or multi-select.
  # Usage, options and the accessibility contract: docs/components/toggle_group.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class ToggleGroupComponent < ApplicationComponent
    BASE = "inline-flex gap-1"

    TYPES = %i[single multiple].freeze

    def initialize(type: :single, value: nil, aria_label: nil, aria_labelledby: nil, **html_attrs)
      @type = type.to_sym
      unless TYPES.include?(@type)
        raise ArgumentError,
          "UI::ToggleGroupComponent: unknown type #{@type.inspect}. " \
          "Expected one of: #{TYPES.join(", ")}."
      end

      name = aria_labelledby || aria_label
      if name.to_s.strip.empty?
        raise ArgumentError,
          "UI::ToggleGroupComponent: a group of toggle buttons needs an accessible " \
          "name — pass aria_label: or aria_labelledby:."
      end

      @value = Array(value).map(&:to_s)
      @aria_label = aria_label
      @aria_labelledby = aria_labelledby
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div,
        content,
        class: cn(BASE, @extra_class),
        role: "group",
        "aria-label": @aria_labelledby ? nil : @aria_label,
        "aria-labelledby": @aria_labelledby,
        "data-controller": "toggle-group",
        "data-toggle-group-type-value": @type,
        **@html_attrs)
    end

    def item_pressed?(item_value)
      @value.include?(item_value.to_s)
    end
  end
end
