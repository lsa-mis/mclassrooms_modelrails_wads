# frozen_string_literal: true

module UI
  # # Toggle
  #
  # A two-state press button — a real `<button type="button">` carrying `aria-pressed`
  # (mirrored as `data-state`) that flips on click via the `toggle` Stimulus controller.
  # Use it for a standalone on/off action (bold, mute, pin), not as a form checkbox.
  #
  # ## Use when
  # - You need a single, instantly-applied on/off action with no separate submit.
  #
  # ## Don't use when
  # - It's a form field whose value posts on submit — use a checkbox/switch input.
  #
  # ## Accessibility contract
  # - **Guarantees:** `aria-pressed` reflecting state, and a 44px-minimum touch target
  #   at every size (AAA 2.5.5 target-size).
  # - **You supply:** an accessible name — visible text/content, or an `aria-label:` for
  #   an icon-only toggle — and a valid `size` (an unknown one raises in development).
  #
  # ## Sizes
  # `default` · `sm` · `lg` — all >=44px tall.
  # @logical_path Forms & Inputs
  class ToggleComponentPreview < ViewComponent::Preview
    include UIHelper

    # Unpressed (off) by default — aria-pressed="false", data-state="off".
    def default
    end

    # Pressed (on) — aria-pressed="true", data-state="on".
    def pressed
    end

    # All sizes render >=44px tall (the AAA target-size floor); sm differs only
    # in width/padding, lg is taller.
    def sizes
    end

    # Edit `label`, `pressed`, and `size` live to explore the component.
    # @param label text
    # @param pressed toggle
    # @param size select [default, sm, lg]
    def playground(label: "Bold", pressed: false, size: :default)
      ui :toggle, label, pressed: pressed, size: size.to_sym
    end

    # ## Don't — icon-only toggle with no accessible name
    #
    # An icon-only toggle **must** carry an `aria-label:`, or screen-reader users hear
    # nothing. Prefer visible text; if the design is truly icon-only, pass a label:
    # `ui :toggle, "★", "aria-label": "Favorite"`.
    # @label Don't · icon-only without a label
    def dont_icon_only_without_label
    end
  end
end
