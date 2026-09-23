# frozen_string_literal: true

module UI
  # # Chip group
  #
  # A multi-select group of chips backed by real checkboxes. The selection posts
  # with the form natively — there is no client-side state, so nothing can disagree
  # with what will actually be submitted.
  #
  # ## Use when
  # - The selection is DATA the server stores: active days, tags, categories.
  # - You want chip styling without giving up native form semantics.
  #
  # ## Don't use when
  # - The selection changes the VIEW rather than the record — a filter, a text-style
  #   toggle. That is `toggle_group`, which is `aria-pressed` buttons and client
  #   state by design. If the choice survives a page reload, it belongs here.
  # - Exactly one option may be chosen. Use `radio_group`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named `role="group"`; every chip is a real focusable
  #   checkbox (`sr-only`, never `hidden`, so it stays keyboard-reachable); the 44px
  #   target floor; checked and focus states key off the input's own state, so what
  #   you see is what will post; focus is an offset OUTLINE, never a ring, scoped to
  #   `:focus-visible`.
  # - **You supply:** a group `label:` or `labelledby:`, an `aria_label:` on any chip
  #   whose visible text is an abbreviation, and on error `invalid:` + `describedby:`.
  # @logical_path Forms & Inputs
  class ChipGroupComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Weekday chips — abbreviated labels, full names announced.
    def default
    end

    # Whole-word labels need no aria_label override.
    def tags
    end

    # A chip that cannot be chosen right now.
    def with_disabled
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — a view filter as a chip group
    #
    # This selection changes what is displayed, not what is stored. A chip group
    # posts it with the form and carries an empty sentinel for a key the server
    # never reads. Use `toggle_group` for view state.
    # @label Don't · view filter
    def dont_view_filter
    end

    # @!endgroup
  end
end
