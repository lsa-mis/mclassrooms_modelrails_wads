# frozen_string_literal: true

module UI
  # # RadioGroup
  #
  # A labelled single-choice control — a `role="radiogroup"` wrapping one native
  # `<input type="radio">` per option, each tied to its own `<label for>`.
  #
  # ## Use when
  # - You are choosing one value from a small, fixed set (a plan, a visibility
  #   level, a cadence).
  #
  # ## Don't use when
  # - There are many or dynamic options — use `ui :select`.
  # - The choice is binary on/off — use `ui :toggle` or `ui :checkbox`.
  #
  # ## Accessibility contract
  # - **Guarantees:** an accessible group name (`aria-label` / `aria-labelledby`),
  #   matched `<label for>`/input `id` per option, and on error `aria-invalid="true"`
  #   plus an `aria-describedby` link to the message.
  # - **You supply:** a group `label:` (or `labelledby:`), `items:` as
  #   `[{ value:, label:, checked?:, disabled?: }]`, and on error `invalid:` +
  #   `describedby:`.
  #
  # ## Related
  # `select` · `checkbox`
  # @logical_path Forms & Inputs
  class RadioGroupComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Baseline: a named group with a few options and no current selection.
    def default
    end

    # One option pre-selected via `checked: true` on its item.
    def with_selection
    end

    # Error state: the group carries `aria-invalid="true"` and `aria-describedby`
    # pointing at a sibling `<p>` that holds the message.
    def invalid
    end

    # @!endgroup

    # @!group Reference

    # Flip `invalid` and watch the group's `aria-invalid` rewire live.
    # @param label text
    # @param invalid toggle
    def playground(label: "Billing plan", invalid: false)
      ui :radio_group, name: "pg_plan", label: label, invalid: invalid,
        items: [ { value: "free", label: "Free" }, { value: "pro", label: "Pro" } ]
    end

    # ## Don't — a radiogroup with no accessible name
    #
    # A `role="radiogroup"` with neither `label:` nor `labelledby:` exposes no
    # accessible name — screen-reader users hear an unlabelled group. Always pass
    # `label:` (or point `labelledby:` at a visible heading).
    # @label Don't · no group label
    def dont_no_group_label
    end

    # @!endgroup
  end
end
