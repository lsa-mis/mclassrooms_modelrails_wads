# frozen_string_literal: true

module UI
  # # Button group
  #
  # A presentational `role="group"` wrapper that segments its children into a
  # single bar: it collapses the inner corners and overlaps the borders so
  # adjacent buttons read as one control. Purely visual — it owns no state, JS,
  # or keyboard behaviour; the buttons inside carry their own a11y contract.
  #
  # ## Use when
  # - Grouping 2–3 related actions or a segmented control (e.g. a view switcher)
  #   into one visual unit.
  #
  # ## Accessibility contract
  # - **Guarantees:** a `role="group"` boundary and the segmented styling.
  # - **You supply:** the child controls (each with its own accessible name) and,
  #   optionally, an `aria_label:` to name the group when context doesn't already.
  # @logical_path Actions
  class ButtonGroupComponentPreview < ViewComponent::Preview
    include UIHelper

    # A segmented control of related actions, named with `aria_label:`.
    def default
    end
  end
end
