# frozen_string_literal: true

module UI
  # # Select
  #
  # A styled native `<select>` for single-choice from a known list. You supply the
  # options and an EXTERNAL `<label for>`; an `id` is always emitted so the label can
  # target it. On error, pass `invalid: true` + `describedby:`.
  #
  # ## Use when
  # - You need a single-choice dropdown from a known, finite list of options.
  #
  # ## Don't use when
  # - The control needs free-text entry or async search — that's a combobox.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA border/focus-ring tokens, an `id` always emitted,
  #   `aria-invalid="true"` when `invalid: true`, and `aria-describedby` wired when
  #   `describedby:` is supplied.
  # - **You supply:** the visible label as an external `<label for="<id>">` — unlike
  #   checkbox, this component does NOT bundle a label.
  #
  # ## Related
  # `combobox` · `radio_group` · `label`
  # @logical_path Forms & Inputs
  class SelectComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # A native select with a sibling label — the baseline appearance.
    def default
    end

    # A pre-selected option (`selected:` matches by value).
    def selected
    end

    # A leading empty option via `include_blank: true` — useful as a "choose one" prompt.
    def include_blank
    end

    # Error state: `aria-invalid="true"` plus `aria-describedby` wired to a sibling
    # error message. In a real form the form builder sets both automatically.
    def invalid
    end

    # Disabled control — passed straight through via `**html_attrs`.
    def disabled
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — a select with no associated label
    #
    # A `<select>` with no external `<label for="<id>">` has no accessible name —
    # screen-reader users hear only "combobox". Always pair it with a label that
    # targets the emitted id.
    # @label Don't · no label
    def dont_no_label
    end

    # @!endgroup
  end
end
