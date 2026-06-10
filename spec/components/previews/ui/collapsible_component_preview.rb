# frozen_string_literal: true

module UI
  # # Collapsible
  #
  # A single CSS-only disclosure, rendered as a native `<details>`/`<summary>`.
  # The browser owns the show/hide and the keyboard (the summary is focusable;
  # Enter/Space toggles), so the component needs no JavaScript.
  #
  # ## Use when
  # - Progressively disclosing one block of content behind a caller-supplied trigger.
  #
  # ## Accessibility contract
  # - **Guarantees:** native disclosure semantics, an AAA `focus-ring` on the
  #   summary, and a hidden native webkit marker.
  # - **You supply:** a `with_trigger` slot (the summary row) and the content.
  #
  # ## Modes
  # Closed (default) · `open: true` (render pre-expanded).
  # @logical_path Data Display
  class CollapsibleComponentPreview < ViewComponent::Preview
    include UIHelper

    # Closed on load — the caller-supplied trigger toggles the content. No JavaScript.
    def default
    end

    # `open: true` renders the disclosure pre-expanded, with richer block content.
    def expanded
    end
  end
end
