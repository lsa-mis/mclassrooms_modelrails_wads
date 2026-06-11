# frozen_string_literal: true

module UI
  # # ToggleGroup
  #
  # A named cluster of `ui :toggle` buttons wired to the `toggle-group` Stimulus
  # controller, which enforces single- or multi-select on click.
  #
  # ## Use when
  # - You have related on/off controls and want one-active-at-a-time (`:single`)
  #   or many-active (`:multiple`) selection in a labelled group.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named grouping (`role="group"` + accessible name) so AT
  #   announces what the buttons control. Focus lives on each item (the `ui :toggle`
  #   AAA `focus-ring`), never the wrapper.
  # - **You supply:** an accessible name via `aria_label:` (or `aria_labelledby:`),
  #   and the toggle items. Each item's `pressed:` should reflect the active value.
  #
  # ## Modes
  # Single-select (`type: :single`) · multi-select (`type: :multiple`).
  #
  # ## Related
  # `toggle`
  # @logical_path Forms & Inputs
  class ToggleGroupComponentPreview < ViewComponent::Preview
    include UIHelper

    # Single-select — only one item active at a time. The controller clears the
    # others on click. "Center" starts pressed to reflect the active value.
    def default
    end

    # Multi-select — several items active simultaneously. Clicking toggles each
    # item independently. "Bold" and "Italic" start pressed.
    def multiple
    end
  end
end
