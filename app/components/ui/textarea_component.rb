# frozen_string_literal: true

module UI
  class TextareaComponent < ApplicationComponent
    # Styling matches the form builder's (`UI::FormBuilder`) field rendering (shared
    # with UI::InputComponent) so `f.text_area` delegates to it invisibly.
    BASE   = "block w-full rounded-md border px-3 py-2 placeholder:text-text-muted " \
             "disabled:cursor-not-allowed disabled:opacity-50 " \
             "focus-ring min-h-[var(--form-input-height)]"
    NORMAL = "border-border-strong bg-surface-raised text-text-heading"
    ERROR  = "border-danger ring-2 ring-danger bg-danger-surface text-danger"

    # value:       textarea body (builder-driven); falls back to block content for standalone use
    # required:    sets `required` + `aria-required="true"`
    # invalid:     applies error styling + `aria-invalid="true"`
    # describedby: sets `aria-describedby`
    def initialize(value: nil, required: false, invalid: false, describedby: nil, **html_attrs)
      @value = value
      @required = required
      @invalid = invalid
      @describedby = describedby
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:textarea, @value || content, **textarea_attrs)
    end

    private

    def textarea_attrs
      attrs = { class: cn(BASE, @invalid ? ERROR : NORMAL, @extra_class) }
      if @required
        attrs[:required] = true
        attrs["aria-required"] = "true"
      end
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      attrs.merge(@html_attrs)
    end
  end
end
