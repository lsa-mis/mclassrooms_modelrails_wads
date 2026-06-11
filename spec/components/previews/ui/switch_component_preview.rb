# frozen_string_literal: true

module UI
  # # Switch
  #
  # A binary on/off toggle backed by a native `<input type="checkbox" role="switch">`.
  # The native `checked` state conveys on/off to assistive tech — no JS, no stale ARIA.
  #
  # ## Use when
  # - An immediate on/off setting (notifications on, dark mode on) that takes effect
  #   on toggle.
  #
  # ## Don't use when
  # - The choice is part of a submitted form, or it isn't strictly binary — use a
  #   checkbox or radio group.
  #
  # ## Accessibility contract
  # - **Guarantees:** a `role="switch"` checkbox whose native `checked` conveys state,
  #   and a >=44px clickable target (AAA 2.5.5) even though the visual track is smaller.
  # - **You supply:** an accessible name (`label:` or `aria-label:`), the initial
  #   `checked:` state, and a `name:` so the value posts.
  # @logical_path Forms & Inputs
  class SwitchComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Off — the default unchecked state.
    def off
    end

    # On — the initial checked state.
    def on
    end

    # With a visible text label, associated with the control.
    def with_label
    end

    # Disabled — non-interactive, dimmed via peer-disabled styling.
    def disabled
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — a switch with no accessible name
    #
    # A label-less switch with no `aria-label:` has nothing to announce — screen-reader
    # users hear only "switch, off". Always pass a `label:` or an `aria-label:`.
    # @label Don't · no accessible name
    def dont_no_label
    end

    # @!endgroup
  end
end
