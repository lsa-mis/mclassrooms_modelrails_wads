# frozen_string_literal: true

module UI
  # # Floating Label
  #
  # A single-line text control whose visible label starts inside the field and
  # floats up on focus or when the field has a value. The label is also the
  # placeholder — the float is pure CSS (the input is `peer`, the label is its
  # later sibling, driven by `peer-focus:` / `peer-[:not(:placeholder-shown)]:`).
  #
  # ## Use when
  # - You want a compact field that combines label + placeholder in one slot
  #   (dense forms, modals, marketing sign-up rows).
  #
  # ## Don't use when
  # - You need persistent help text below the field, or a multi-line control —
  #   use `ui :input` / `ui :textarea` with a normal `<label>`.
  # - The form is managed by `form_with` and the form builder already renders the
  #   label, error, and ARIA wiring — call `f.text_field` instead.
  #
  # ## Accessibility contract
  # - **Guarantees:** the label bundles with the control and is always associated
  #   via `for`/`id` (an `id` is always emitted, even with no `id`/`name`); AAA
  #   border/focus-ring tokens; an `h-12` (48 px) target; `required` +
  #   `aria-required="true"` when `required: true`; `aria-invalid="true"` when
  #   `invalid: true`; `aria-describedby` wired when `describedby:` is supplied.
  # - **You supply:** a `label` (it doubles as the placeholder the float needs) and,
  #   on error, `invalid: true` + `describedby:` pointing at a sibling error element.
  # @logical_path Forms & Inputs
  class FloatingLabelComponentPreview < ViewComponent::Preview
    include UIHelper

    # The baseline: a floating-label text field. The label sits inside the field
    # until focus or input, then rises.
    def default
    end

    # Required field — emits `required` + `aria-required="true"`.
    def required
    end

    # Error state: `aria-invalid="true"` (red border via the `aria-invalid:` hooks)
    # plus `aria-describedby` wired to a sibling error message. In a real form the
    # form builder sets both automatically when an ActiveModel error is present.
    def invalid
    end

    # ## Don't — a floating label with no label text
    #
    # Without a `label` there's no placeholder to drive the float AND no accessible
    # name — screen-reader users hear only "edit text". The visible label IS the
    # accessible name here, so it is never optional.
    # @label Don't · no label
    def dont_no_label
    end
  end
end
