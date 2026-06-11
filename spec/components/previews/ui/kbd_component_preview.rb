# frozen_string_literal: true

module UI
  # # Kbd
  #
  # A small inline chip representing a keyboard key or shortcut (`<kbd>`). Purely
  # presentational and non-interactive — it labels a key, it is never itself a target.
  #
  # ## Use when
  # - Documenting a keyboard shortcut inline ("Press ⌘K to search") or inside a
  #   menu item / tooltip.
  #
  # ## Don't use when
  # - The text isn't a keyboard key — `<kbd>` misrepresents semantics to assistive
  #   tech. Use plain text or a `badge` for non-key labels.
  # - You need it to be clickable — it is `pointer-events-none` by contract.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA-contrast text on `bg-surface-sunken` and a
  #   non-interactive, unselectable chip.
  # - **You supply:** the key text (positional arg, `label:`, or slot content).
  # @logical_path Data Display
  class KbdComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # A single key.
    def default
    end

    # A shortcut combination — one <kbd> per key.
    def combo
    end

    # Inline within running text.
    def in_context
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — non-keyboard text in a <kbd>
    #
    # `<kbd>` means "keyboard input". Using it for a button label or arbitrary text
    # misrepresents semantics to screen readers. Use plain text or a `badge` instead.
    # @label Don't · non-key text
    def dont_non_key
    end

    # @!endgroup
  end
end
