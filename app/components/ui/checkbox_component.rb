# frozen_string_literal: true

module UI
  # A single labelled native checkbox — the form-control pattern-setter for the library (radio_group and switch copy its `invalid:` / `describedby:` / id-fallback API).
  # Usage, options and the accessibility contract: docs/components/checkbox.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class CheckboxComponent < ApplicationComponent
    BASE = "peer size-4 shrink-0 rounded-[4px] border border-border-strong shadow-xs transition-shadow outline-none " \
           "focus-ring " \
           "disabled:cursor-not-allowed disabled:opacity-50 " \
           "aria-invalid:border-2 aria-invalid:border-danger " \
           "checked:border-interactive checked:bg-interactive checked:text-text-on-interactive " \
           " "

    # invalid: drives the app's server-validation-driven aria-invalid posture.
    # describedby: wires the input to its error message's id (aria-describedby).
    # indeterminate: tri-state ("some children checked"). No HTML attribute exists for it,
    #   so a controller sets the DOM property on connect and clears it once the user acts.
    def initialize(label: nil, checked: false, invalid: false, describedby: nil,
      indeterminate: false, **html_attrs)
      @label = label
      @checked = checked
      @indeterminate = indeterminate
      @invalid = invalid
      @describedby = describedby
      # Always resolve an id so the label association never breaks: explicit id →
      # sanitized name → an object-based fallback (mirrors the switch template).
      @id = html_attrs[:id] || html_attrs[:name]&.gsub(/\W/, "_") || "checkbox_#{object_id}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      if @label
        content_tag(:div, class: "flex items-center gap-2") do
          concat checkbox_input
          concat label_tag
        end
      else
        checkbox_input
      end
    end

    private

    def checkbox_input
      attrs = @html_attrs.merge(
        type: "checkbox",
        id: @id,
        class: cn(BASE, @extra_class)
      )
      attrs[:checked] = true if @checked
      if @indeterminate
        caller_data = attrs.delete(:data) || {}
        attrs[:data] = {
          controller: [ caller_data[:controller], "indeterminate" ].compact.join(" "),
          action: [ caller_data[:action], "change->indeterminate#clear" ].compact.join(" ")
        }.merge(caller_data.except(:controller, :action))
      end
      attrs[:"aria-invalid"] = "true" if @invalid
      attrs[:"aria-describedby"] = @describedby if @describedby
      content_tag(:input, nil, **attrs)
    end

    # The label is the input's peer sibling so `peer-disabled:` style hooks apply,
    # and it is the larger clickable pointer target that satisfies AAA 2.5.5 — the
    # visual control stays size-4 (16px) by design; do not bloat it.
    def label_tag
      content_tag(:label,
        @label,
        for: @id,
        class: "inline-flex min-h-input items-center text-sm font-medium peer-disabled:cursor-not-allowed peer-disabled:opacity-50")
    end
  end
end
