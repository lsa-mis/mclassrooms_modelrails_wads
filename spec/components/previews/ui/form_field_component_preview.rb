# frozen_string_literal: true

module UI
  # # Form Field
  #
  # A hand-composed labelled field: binds `<label for>` to the control, gives the
  # hint/error real ids referenced by the control's `aria-describedby`, and injects
  # `invalid`/`required`. The control arrives as a block; spread `**f.input_attrs`
  # onto it to adopt the field's id + aria wiring.
  #
  # ## Use when
  # - Composing a one-off labelled field by hand. For model-backed forms, prefer the
  #   app's form builder — it already does this wiring.
  #
  # ## Accessibility contract
  # - **Guarantees:** a bound `<label for=id>`, hint/error with `#{id}-hint`/`#{id}-error`
  #   ids, and `input_attrs` carrying id + describedby + invalid + required. The
  #   required `*` is a decorative aria-hidden mark on the label.
  # - **You supply:** the control inside the block, spread with `**f.input_attrs`.
  #
  # ## Related
  # `input` · `label` · `textarea` · `select` · `checkbox` · `radio_group`
  # @logical_path Forms & Inputs
  class FormFieldComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Label + control, no hint or error.
    def default
    end

    # A hint paragraph (id `{id}-hint`) referenced by the control's aria-describedby.
    def with_hint
    end

    # An error paragraph (role=alert, id #{id}-error) — the control gets aria-invalid
    # and aria-describedby pointing at it.
    def with_error
    end

    # A required field — decorative `*` on the label; the control carries `required`.
    def required
    end

    # @!endgroup

    # @!group Reference

    # The teaching playground: flip `required`, set/clear `hint` and `error`, and watch
    # the ARIA rewire — hint/error get real ids referenced by the control's
    # `aria-describedby`; an error also sets `aria-invalid`; required adds the
    # decorative `*` and the control's `required`.
    # @param label text
    # @param hint text
    # @param error text
    # @param required toggle
    def playground(label: "Email", hint: "We'll never share it.", error: "", required: false)
      render_with_template(locals: { label: label, hint: hint, error: error, required: required })
    end

    # @!endgroup
  end
end
