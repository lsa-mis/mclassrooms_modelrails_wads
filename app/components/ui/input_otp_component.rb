# frozen_string_literal: true

module UI
  # A one-time-passcode entry: a labelled `role="group"` of N single-character inputs that auto-advance on entry, walk with Arrow/Backspace keys, and accept a full-code paste (the `input-otp` Stimulus controller spreads pasted digits across the cells).
  # Usage, options and the accessibility contract: docs/components/input_otp.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class InputOtpComponent < ApplicationComponent
    CELL_CLS = "h-12 w-11 rounded-md border border-border-strong bg-surface-raised text-text-heading " \
               "text-center text-lg font-medium shadow-xs transition-colors focus-ring " \
               "aria-invalid:border-2 aria-invalid:border-danger " \
               "disabled:pointer-events-none disabled:opacity-50"

    WRAPPER_CLS = "flex items-center gap-2"
    SEPARATOR_CLS = "text-text-muted text-lg font-medium"

    # length:    number of OTP digits (default 6); must be a positive integer
    # name:      form field name (individual cells post as name[0], name[1], …)
    # label:     group accessible name (defaults to the i18n "One-time passcode")
    # separator: position (Integer) or Hash { position => char }, e.g. 3 or { 3 => "-" }
    def initialize(length: 6, name: "otp", label: nil, separator: nil, **html_attrs)
      @length = length.to_i
      # Fail loud: a non-positive length is a programming error (renders an empty
      # group with no inputs), not a styleable state.
      raise ArgumentError, "UI::InputOtpComponent: length must be a positive integer, got #{length.inspect}" if @length < 1

      @name      = name
      @label     = label
      @separator = case separator
      when Integer then { separator => "-" }
      when Hash    then separator
      end
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:div, **group_attrs) do
        @length.times do |i|
          sep = @separator&.fetch(i, nil)
          concat content_tag(:span, sep, class: SEPARATOR_CLS, "aria-hidden": "true") if sep
          concat digit_input(i)
        end
      end
    end

    private

    # Component wins on its a11y contract: merge caller html_attrs FIRST, then apply
    # role/aria-label as overrides so a caller can't clobber the group's role or
    # accessible name. Keys are stringified so an override lands on the same key
    # whether the caller passed `role:`/`"role"` (and likewise aria).
    def group_attrs
      attrs = { "class" => cn(WRAPPER_CLS, @extra_class) }
      @html_attrs.each { |k, v| attrs[k.to_s] = v }
      # Deep-merge caller data with the controller wiring so a passed-through
      # `data:` can't drop `data-controller` (and the controller can't clobber a
      # caller's data-*).
      attrs["data"] = (attrs["data"] || {}).merge(controller: "input-otp")
      attrs["role"] = "group"
      attrs["aria-label"] = group_label
      attrs
    end

    def group_label
      @label.presence || I18n.t("modelrails_ui.input_otp.label", default: "One-time passcode")
    end

    def digit_input(index)
      content_tag(:input, nil,
        type: "text",
        inputmode: "numeric",
        autocomplete: "one-time-code",
        maxlength: 1,
        name: "#{@name}[#{index}]",
        class: CELL_CLS,
        "aria-label": I18n.t("modelrails_ui.input_otp.digit", default: "Digit %{index} of %{total}", index: index + 1, total: @length),
        data: {
          input_otp_target: "cell",
          action: "input->input-otp#onInput keydown->input-otp#onKeydown paste->input-otp#onPaste"
        })
    end
  end
end
