# frozen_string_literal: true

module UI
  # # Popover
  #
  # A non-modal floating panel anchored to a trigger button, driven by the `floating`
  # Stimulus controller. Click the trigger to toggle; Escape or an outside click closes
  # it and returns focus to the trigger. Placement is CSS anchor positioning, so the panel
  # flips to stay on-screen and is promoted to the top layer rather than being buried by a
  # `sticky` or `backdrop-blur` ancestor.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<button>` trigger with `aria-haspopup="dialog"`,
  #   `aria-expanded`, and `aria-controls`; a `role="dialog"` panel named by `label:`.
  #   Non-modal — focus is not trapped.
  # - **You supply:** `label:` (the panel's accessible name) and a `with_trigger` slot.
  #
  # ## Related
  # `tooltip` · `hover_card`
  # @logical_path Overlays
  class PopoverComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Standard popover: a button trigger and a labelled dialog panel.
    def basic
    end

    # `side:` and `align:` place the panel relative to the trigger.
    def positioned
    end

    # A trigger inside a `sticky z-40` header — a stacking context the panel's own `z-50`
    # cannot escape. Anchor positioning lets the panel be promoted to the top layer, so it
    # paints over the page while staying tethered to its trigger.
    def inside_stacking_context
    end

    # @!endgroup

    # @!group Reference

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

    # @!endgroup
  end
end
