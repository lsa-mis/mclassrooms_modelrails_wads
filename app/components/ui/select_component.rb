# frozen_string_literal: true

module UI
  # # Select
  #
  # A styled native `<select>`; you supply options + an external form `<label for>`
  # (an `id` is always emitted so the label can target it), and on error
  # `invalid: true` + `describedby:`.
  #
  # ## Use when
  # - You need a single-choice dropdown from a known, finite list of options.
  #
  # ## Don't use when
  # - The control needs free-text entry or async search — that's a combobox, not a
  #   native `<select>`.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA border/focus-ring tokens, an `id` ALWAYS emitted on the
  #   `<select>`, `aria-invalid="true"` when `invalid: true`, and `aria-describedby`
  #   wired when `describedby:` is supplied.
  # - **You supply:** the visible label as an EXTERNAL `<label for="<id>">` — unlike
  #   checkbox, this component does NOT bundle a label (a `<select>` is conventionally
  #   labeled by a separate form label). On error, pass `invalid: true` and point
  #   `describedby:` at the error element's id.
  #
  # No fail-loud guard — there's no enum axis to validate.
  class SelectComponent < ApplicationComponent
    BASE = "flex min-h-[var(--form-input-height)] w-full rounded-md border border-border-strong bg-transparent px-3 py-1 text-sm shadow-sm " \
           "outline-none focus-visible:border-border-focus focus-ring " \
           "aria-invalid:border-danger-border aria-invalid:ring-danger " \
           "disabled:cursor-not-allowed disabled:opacity-50"

    # options: array of strings, or [value, label] pairs, or { value: label } hash
    #   invalid:     sets `aria-invalid="true"` (absent when false)
    #   describedby: sets `aria-describedby` (link to the error/hint element id)
    def initialize(options: [], selected: nil, include_blank: false, invalid: false, describedby: nil, **html_attrs)
      @options = options
      @selected = selected
      @include_blank = include_blank
      @invalid = invalid
      @describedby = describedby
      # External-label association: an id is ALWAYS emitted so a sibling
      # `<label for>` can target this control. Prefer an explicit id, fall back to a
      # sanitized name, then a stable per-instance id.
      @id = html_attrs[:id] || html_attrs[:name]&.gsub(/\W/, "_") || "select_#{object_id}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:select, **select_attrs) do
        safe_join(option_tags)
      end
    end

    private

    def select_attrs
      attrs = @html_attrs.merge(id: @id, class: cn(BASE, @extra_class))
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      attrs
    end

    def option_tags
      tags = []
      tags << content_tag(:option, "", value: "") if @include_blank
      normalized_options.each do |(val, label)|
        attrs = { value: val }
        attrs[:selected] = true if val.to_s == @selected.to_s
        tags << content_tag(:option, label, **attrs)
      end
      tags
    end

    def normalized_options
      case @options
      when Hash  then @options.map { |v, l| [ v, l ] }
      when Array then @options.map { |o| o.is_a?(Array) ? o : [ o, o ] }
      else []
      end
    end
  end
end
