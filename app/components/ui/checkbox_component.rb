# frozen_string_literal: true

module UI
  # # Checkbox
  #
  # A single labelled native checkbox — the form-control pattern-setter for the
  # library (radio_group and switch copy its `invalid:` / `describedby:` / id-fallback
  # API). Renders a native `<input type="checkbox">` so it inherits the browser's
  # keyboard operability and form semantics for free.
  #
  # ## Use when
  # - A single on/off choice tied to a label: "Accept terms", "Remember me",
  #   "Email me about updates".
  #
  # ## Don't use when
  # - It's an immediate-effect setting toggle with no form submit — use `switch`.
  # - You have a mutually-exclusive set of options — use `radio_group`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a labelled, keyboard-operable checkbox with an AAA focus ring.
  #   The control always carries an `id` (falling back from `id` → sanitized `name`
  #   → object-based id) so the `<label for=...>` association never breaks, and the
  #   clickable label provides the larger pointer target (AAA 2.5.5 target-size).
  # - **You supply:** a `label` and, on error, `invalid: true` (sets `aria-invalid`)
  #   plus `describedby:` pointing at the error message's id.
  #
  # No variant axis (single appearance), so there is no `coerce_variant` fail-loud
  # guard here — unlike the enum-driven components (alert, button).
  class CheckboxComponent < ApplicationComponent
    BASE = "peer size-4 shrink-0 rounded-[4px] border border-border-strong shadow-xs transition-shadow outline-none " \
           "focus-ring " \
           "disabled:cursor-not-allowed disabled:opacity-50 " \
           "aria-invalid:border-danger-border aria-invalid:ring-danger  " \
           "checked:border-interactive checked:bg-interactive checked:text-text-on-interactive " \
           " "

    # invalid: drives the app's server-validation-driven aria-invalid posture.
    # describedby: wires the input to its error message's id (aria-describedby).
    def initialize(label: nil, checked: false, invalid: false, describedby: nil, **html_attrs)
      @label = label
      @checked = checked
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
        class: "inline-flex min-h-11 items-center text-sm font-medium peer-disabled:cursor-not-allowed peer-disabled:opacity-50")
    end
  end
end
