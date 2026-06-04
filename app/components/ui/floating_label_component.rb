# frozen_string_literal: true

module UI
  class FloatingLabelComponent < ApplicationComponent
    WRAPPER = "relative w-full"

    # The label floats via CSS peer — it sits inside the input border initially,
    # then rises above when the input is focused or has a value (:not(:placeholder-shown)).
    INPUT_BASE = "peer h-12 w-full min-w-0 rounded-md border border-border-strong bg-transparent px-3 pb-1.5 pt-4 " \
                 "text-base shadow-xs transition-[color,box-shadow] outline-none placeholder:text-transparent " \
                 "focus-visible:border-border-focus focus-visible:ring-[3px] focus-visible:ring-interactive-focus " \
                 "aria-invalid:border-danger-border aria-invalid:ring-danger  " \
                 "disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 " \
                 "md:text-sm "

    LABEL_BASE = "pointer-events-none absolute left-3 top-3 origin-[0_0] text-sm text-text-muted " \
                 "transition-all duration-200 " \
                 "peer-focus:-translate-y-2 peer-focus:scale-75 peer-focus:text-text-heading " \
                 "peer-[:not(:placeholder-shown)]:-translate-y-2 peer-[:not(:placeholder-shown)]:scale-75"

    # Mirrors the input form-control API so the floating-label variant carries the
    # same accessibility contract:
    #   label:       visible label text — also the placeholder, which the
    #                `:not(:placeholder-shown)` peer trick needs to drive the float (required)
    #   type:        input type, default "text"
    #   id:          ties label[for] to input; falls back to name, then a per-object id
    #   required:    sets the HTML `required` attribute AND `aria-required="true"`
    #   invalid:     sets `aria-invalid="true"`, activating the `aria-invalid:` style hooks
    #   describedby: sets `aria-describedby` (link to hint/error element ids)
    #
    # Note: no fail-loud guard on `label` — the missing-keyword ArgumentError is the
    # guard, and `label` is also the placeholder the float mechanism depends on.
    def initialize(label:, type: "text", id: nil, required: false, invalid: false, describedby: nil, **html_attrs)
      @label = label
      @type  = type
      @required = required
      @invalid = invalid
      @describedby = describedby
      # Always resolve an id so the label's `for` always ties to the input.
      @id = id || html_attrs[:id] || html_attrs[:name]&.to_s&.gsub(/\W/, "_") || "floating_label_#{object_id}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:div, class: WRAPPER) do
        concat input_tag
        concat label_tag
      end
    end

    private

    def input_tag
      # id is ALWAYS present so the for/id association can never break.
      attrs = { type: @type, id: @id, placeholder: @label, class: cn(INPUT_BASE, @extra_class) }
      if @required
        attrs[:required] = true
        attrs["aria-required"] = "true"
      end
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      content_tag(:input, nil, **attrs, **@html_attrs)
    end

    def label_tag
      content_tag(:label, @label, class: LABEL_BASE, for: @id)
    end
  end
end
