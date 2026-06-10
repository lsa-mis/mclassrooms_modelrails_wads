# frozen_string_literal: true

module UI
  # # Popover
  #
  # A non-modal floating panel anchored to a trigger button, driven by the `floating`
  # Stimulus controller. Click the trigger to toggle; Escape or an outside click closes
  # it and returns focus to the trigger.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<button>` trigger with `aria-haspopup="dialog"`,
  #   `aria-expanded`, and `aria-controls`; a `role="dialog"` panel named by `label:`.
  #   Non-modal — focus is not trapped.
  # - **You supply:** `label:` (the panel's accessible name) and a `with_trigger` slot.
  # @logical_path Overlays
  class PopoverComponentPreview < ViewComponent::Preview
    include UIHelper

    # Standard popover: a button trigger and a labelled dialog panel.
    def basic
    end

    # `side:` and `align:` place the panel relative to the trigger.
    def positioned
    end

    # Edit `side`, `align`, and `label` live to explore placement. Popover renders
    # inline (not a full-screen modal), so the param panel is the natural way to
    # sweep its positioning matrix.
    # @param label text
    # @param side select [bottom, top, left, right]
    # @param align select [start, center, end]
    def playground(label: "Account menu", side: :bottom, align: :start)
      ui :popover, label: label, side: side.to_sym, align: align.to_sym do |c|
        c.with_trigger { "Open popover" }
        "Panel anchored #{side}/#{align}. Change the params to explore placement."
      end
    end
  end
end
