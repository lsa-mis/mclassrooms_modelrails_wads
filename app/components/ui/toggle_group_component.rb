# frozen_string_literal: true

module UI
  # # ToggleGroup
  #
  # A grouping of related toggle buttons (`ui :toggle`) wired to the
  # `toggle-group` Stimulus controller, which enforces single- or multi-select.
  #
  # ## Use when
  # - You have a set of related on/off controls and want either one-active-at-a-time
  #   (`:single` — text alignment, view mode) or many-active (`:multiple` —
  #   bold/italic/underline) selection in a labelled cluster.
  #
  # ## Don't use when
  # - It's a single standalone on/off control — use `ui :toggle` on its own.
  # - It's a form field that posts on submit — use a radio group or checkboxes.
  #
  # ## Accessibility contract
  # - **Guarantees:** the cluster is a named grouping (`role="group"` + an accessible
  #   name) so AT announces what the buttons control; `data-toggle-group-type-value`
  #   tells the controller how to enforce selection. Focus lives on each item (the
  #   caller-supplied `ui :toggle` carries the AAA `focus-ring`), never the wrapper.
  # - **You supply:** an accessible name via `aria_label:` OR `aria_labelledby:`
  #   (a nameless group of toggle buttons is unannounced — so this fails loud rather
  #   than ship an anonymous "group"), and the toggle items as block content. Each
  #   item's initial pressed state should reflect `item_pressed?(item_value)`.
  #
  # ## ARIA semantics: `role="group"` for BOTH single and multiple
  # The items are toggle BUTTONS (`<button aria-pressed>`), and the `toggle-group`
  # controller flips their `aria-pressed` — it never emits `role="radio"` /
  # `aria-checked`. A `role="radiogroup"` wrapper requires children with
  # `role="radio"` + `aria-checked`; pairing it with `aria-pressed` buttons would be
  # an ARIA lie that breaks AT. So `:single` keeps `role="group"` (a single-select
  # cluster of pressed buttons — APG toolbar-adjacent) rather than masquerading as a
  # radiogroup. FOLLOW-UP: a true radiogroup variant (role="radio" items +
  # arrow-key roving) is a larger change — out of scope for this hardening pass.
  #
  # ## Parameters
  # - `type:`            `:single` (one active) | `:multiple` (many active)
  # - `value:`           currently active value (String) for `:single`, or an array
  #                      of active values for `:multiple`
  # - `aria_label:`      accessible name for the group
  # - `aria_labelledby:` id of an existing element that names the group
  # - `**html_attrs`     forwarded to the `<div role="group">` wrapper
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
