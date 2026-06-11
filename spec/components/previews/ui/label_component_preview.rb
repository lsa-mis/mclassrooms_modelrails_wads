# frozen_string_literal: true

module UI
  # # Label
  #
  # The caption for a form control. Bind it to an input with `for:` (the control's
  # `id`) so clicking the caption focuses the control and screen readers announce
  # the control's name.
  #
  # ## Use when
  # - Captioning any form control (`input`, `textarea`, `select`). Pair `for:` with
  #   the control's `id`.
  #
  # ## Don't use when
  # - The control self-labels (`checkbox`, `radio_group`) — don't wrap it again.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA-contrast caption text and a `for=` association. The
  #   `required:` `*` is decorative (aria-hidden) — the requirement lives on the
  #   input, never the caption.
  # - **You supply:** the caption text and, to bind it, the control's `id` via `for:`.
  #
  # ## Related
  # `form_field` · `input` · `select`
  # @logical_path Forms & Inputs
  class LabelComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # A standalone caption (no association — see `for_an_input` to bind one).
    def default
    end

    # Bound to an input via `for:` — clicking the caption focuses the field.
    def for_an_input
    end

    # required: true adds a decorative `*`; the input carries aria-required.
    def required
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — a required marker without the requirement on the input
    #
    # The `*` is decorative (aria-hidden). If the input lacks `aria-required`/
    # `required`, screen-reader users never learn the field is mandatory. Always
    # convey the requirement on the control, not just the caption.
    # @label Don't · marker-only requirement
    def dont_marker_only
    end

    # @!endgroup
  end
end
