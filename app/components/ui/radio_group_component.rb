# frozen_string_literal: true

module UI
  # # RadioGroup
  #
  # A labelled radio group — a `role="radiogroup"` wrapping one native
  # `<input type="radio">` per option, each tied to its own `<label for>`.
  #
  # ## Use when
  # - You need a single-choice control over a small, fixed set of options
  #   (a billing plan, a visibility level, a notification cadence).
  #
  # ## Don't use when
  # - There are many options or they're loaded dynamically — use `ui :select`.
  # - The choice is binary on/off — use `ui :toggle` or `ui :checkbox`.
  #
  # ## Accessibility contract
  # - **Guarantees:** the group exposes an accessible name (`aria-label` from `label:`,
  #   or `aria-labelledby` from `labelledby:`), each option's `<label for>` matches its
  #   input `id`, and on error the group carries `aria-invalid="true"` plus an
  #   `aria-describedby` link to the error/hint element.
  # - **You supply:** a group `label:` (or `labelledby:`), `items:` as
  #   `[{ value:, label:, checked?:, disabled?: }]`, and on error `invalid:` +
  #   `describedby:` pointing at a sibling element that holds the message.
  #
  # No fail-loud guard — there is no enum axis to validate.
  class RadioGroupComponent < ApplicationComponent
    # items: [{ value:, label:, checked: (optional), disabled: (optional) }]
    #
    # Group accessibility/form params, mirroring the shared form-control API:
    #   label:       sets the group's accessible name via `aria-label`
    #   labelledby:  sets `aria-labelledby` (point at a visible heading's id instead)
    #   invalid:     sets `aria-invalid="true"` on the group
    #   describedby: sets `aria-describedby` on the group (link to hint/error ids)
    def initialize(name:, label: nil, labelledby: nil, items: [], invalid: false, describedby: nil, **html_attrs)
      @name = name
      @label = label
      @labelledby = labelledby
      @items = items
      @invalid = invalid
      @describedby = describedby
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, **group_attrs) do
        if @items.any?
          safe_join(@items.map { |item| radio_item(item) })
        else
          content
        end
      end
    end

    private

    def group_attrs
      # Component wins on its a11y contract: merge caller html_attrs FIRST, then
      # apply role/aria as overrides so a caller can't clobber the group's
      # accessible name, invalid state, or radiogroup role. Keys are stringified
      # so the overrides land on the same key whether the caller passed `role:`
      # or `"role"` (and likewise for the aria-* attributes).
      attrs = { "class" => cn("grid gap-2", @extra_class) }
      @html_attrs.each { |k, v| attrs[k.to_s] = v }
      attrs["role"] = "radiogroup"
      attrs["aria-label"] = @label if @label.present?
      attrs["aria-labelledby"] = @labelledby if @labelledby.present?
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      attrs
    end

    def radio_item(item)
      id = "#{@name}_#{item[:value].to_s.gsub(/\W/, "_")}"
      content_tag(:div, class: "flex items-center gap-2") do
        concat radio_input(item, id)
        concat radio_label(item, id)
      end
    end

    def radio_input(item, id)
      attrs = { type: "radio", name: @name, value: item[:value], id: id,
                class: "h-4 w-4 border border-interactive text-interactive accent-interactive " \
                       "focus-ring " \
                       "disabled:cursor-not-allowed disabled:opacity-50" }
      attrs[:checked] = true if item[:checked]
      attrs[:disabled] = true if item[:disabled]
      content_tag(:input, nil, **attrs)
    end

    def radio_label(item, id)
      content_tag(:label, item[:label],
        for: id,
        class: "text-sm font-medium leading-none")
    end
  end
end
