# frozen_string_literal: true

module UI
  # A multi-select group of chips backed by real checkboxes — the selection posts with the form natively, with no client-side state to keep in sync.
  # Usage, options and the accessibility contract: docs/components/chip_group.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class ChipGroupComponent < ApplicationComponent
    GROUP = "flex flex-wrap gap-2"

    # The checkbox is `sr-only` INSIDE the label, so the whole chip is the hit area
    # and the control stays a real, focusable checkbox. Everything visual keys off
    # the input's own state with `has-[]`, so there is no class to toggle in JS and
    # nothing that can disagree with what will actually be submitted.
    #
    # Focus is an offset OUTLINE, never a ring: a box-shadow ring is clipped by an
    # `overflow:hidden` ancestor and vanishes in forced-colors mode (2.4.7). Scoped
    # to `:focus-visible` so a pointer press does not paint one. Same treatment as
    # `wysiwyg`'s wrapper.
    CHIP = "inline-flex min-h-input min-w-11 cursor-pointer items-center justify-center " \
           "rounded-md border border-border-strong bg-surface-raised px-3 " \
           "text-sm font-medium text-text-body transition-colors " \
           "has-[:checked]:border-interactive has-[:checked]:bg-interactive " \
           "has-[:checked]:text-text-on-interactive " \
           "has-[:focus-visible]:outline has-[:focus-visible]:outline-2 " \
           "has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-interactive-focus " \
           "has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-50"

    # items: [{ value:, label:, aria_label: (optional), checked: (optional),
    #           disabled: (optional) }]
    #
    #   aria_label: the spoken name when the visible text is an abbreviation — a
    #   chip reading "Mon" announcing "Monday". Omit it and the visible text is the
    #   name, which is what you want whenever the label is already a whole word.
    #
    # Group accessibility/form params, mirroring radio_group's shared API:
    #   label:          the group's accessible name via `aria-label`
    #   labelledby:     `aria-labelledby` (point at a visible heading instead)
    #   invalid:        sets `aria-invalid="true"` on the group
    #   describedby:    `aria-describedby` (link to hint/error ids)
    #   include_hidden: emit the empty sentinel (see #hidden_sentinel)
    def initialize(name:, items: [], label: nil, labelledby: nil, invalid: false,
      describedby: nil, include_hidden: true, **html_attrs)
      @name = name.to_s.end_with?("[]") ? name.to_s : "#{name}[]"
      @items = items
      @label = label
      @labelledby = labelledby
      @invalid = invalid
      @describedby = describedby
      @include_hidden = include_hidden
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, **group_attrs) do
        safe_join([ hidden_sentinel, *@items.map { |item| chip(item) } ].compact)
      end
    end

    private

    def group_attrs
      # Component wins on its a11y contract: the caller's attrs merge FIRST, then
      # role/aria land as overrides, so a caller cannot clobber the group's role,
      # accessible name or invalid state. Keys are stringified so an override lands
      # on the same key whether the caller wrote `role:` or `"role"`.
      attrs = { "class" => cn(GROUP, @extra_class) }
      @html_attrs.each { |key, value| attrs[key.to_s] = value }
      attrs["role"] = "group"
      attrs["aria-label"] = @label if @label.present?
      attrs["aria-labelledby"] = @labelledby if @labelledby.present?
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      attrs
    end

    # Unchecking every chip otherwise submits NOTHING for this key, and the server
    # reads "no change" where the user meant "none" — the classic checkbox-array
    # bug. The empty sentinel makes the key always present; strip the "" server-side
    # (`Array(params[:days]).reject(&:blank?)`). Opt out with `include_hidden: false`
    # when the form already carries its own.
    def hidden_sentinel
      return unless @include_hidden

      tag.input(type: "hidden", name: @name, value: "")
    end

    # `prefs[days][]` → `prefs_days_mon`. Runs of non-word characters collapse to one
    # underscore and the edges are trimmed, so the bracket syntax does not leave
    # doubled or trailing separators in the id a <label for> has to match.
    def chip_id(value)
      base = @name.delete_suffix("[]").gsub(/\W+/, "_").gsub(/\A_+|_+\z/, "")
      "#{base}_#{value.to_s.gsub(/\W+/, "_")}"
    end

    def chip(item)
      id = chip_id(item[:value])
      content_tag(:label, for: id, class: CHIP) do
        safe_join([ chip_input(item, id), chip_text(item) ])
      end
    end

    def chip_input(item, id)
      attrs = { type: "checkbox", id: id, name: @name, value: item[:value], class: "sr-only" }
      attrs[:checked] = true if item[:checked]
      attrs[:disabled] = true if item[:disabled]
      tag.input(**attrs)
    end

    def chip_text(item)
      content_tag(:span, item[:label], "aria-label": item[:aria_label].presence)
    end
  end
end
