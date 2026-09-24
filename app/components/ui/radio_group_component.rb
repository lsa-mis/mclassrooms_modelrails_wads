# frozen_string_literal: true

module UI
  # A labelled radio group — a `role="radiogroup"` wrapping one native `<input type="radio">` per option, each tied to its own `<label for>`.
  # Usage, options and the accessibility contract: docs/components/radio_group.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class RadioGroupComponent < ApplicationComponent
    # items: [{ value:, label:, description: (optional), checked: (optional),
    #           disabled: (optional) }]
    #
    #   description: a supporting line for THAT option. Rendered beside the label
    #   and linked to the input with aria-describedby, so it is announced after the
    #   option's name rather than becoming part of it.
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
      id = radio_id(item[:value])
      described = item[:description].present?
      # items-start only when there is a description to stack: an undescribed row
      # keeps the centred alignment it has always had.
      content_tag(:div, class: cn("flex gap-2", described ? "items-start" : "items-center")) do
        concat radio_input(item, id, described ? description_id(id) : nil)
        concat(described ? described_label(item, id) : radio_label(item, id))
      end
    end

    # `workspace[join_policy]` + `invite` → `workspace_join_policy_invite`. The
    # NAME is sanitised as well as the value: a Rails field name is the ordinary
    # case here and it is full of brackets, which are legal in an HTML5 id but do
    # not parse in a CSS id selector — `#workspace[join_policy]_invite` reads as
    # `#workspace` plus an attribute condition, so every consumer of the id has to
    # know to escape it. Runs collapse to one underscore and the edges are trimmed
    # so the bracket syntax leaves no doubled or trailing separators. Same rule as
    # chip_group's `chip_id`. The posted name itself is untouched — Rails needs the
    # brackets to parse the params. (#247)
    def radio_id(value)
      base = @name.to_s.gsub(/\W+/, "_").gsub(/\A_+|_+\z/, "")
      "#{base}_#{value.to_s.gsub(/\W+/, "_")}"
    end

    def description_id(id) = "#{id}_description"

    # The description is a SIBLING of the label, never inside it. Inside, it would
    # become part of the radio's accessible name and be read as the option itself;
    # as a sibling linked by aria-describedby it is announced after the name, which
    # is what a supporting line is for (#137).
    def described_label(item, id)
      content_tag(:div, class: "grid") do
        concat radio_label(item, id)
        concat content_tag(:p, item[:description], id: description_id(id),
          class: "text-sm text-text-muted")
      end
    end

    def radio_input(item, id, describedby = nil)
      attrs = { type: "radio", name: @name, value: item[:value], id: id,
                class: "h-4 w-4 border border-interactive text-interactive accent-interactive " \
                       "focus-ring " \
                       "disabled:cursor-not-allowed disabled:opacity-50" }
      attrs[:checked] = true if item[:checked]
      attrs[:disabled] = true if item[:disabled]
      attrs["aria-describedby"] = describedby if describedby
      content_tag(:input, nil, **attrs)
    end

    def radio_label(item, id)
      content_tag(:label, item[:label],
        for: id,
        class: "inline-flex min-h-input items-center text-sm font-medium")
    end
  end
end
