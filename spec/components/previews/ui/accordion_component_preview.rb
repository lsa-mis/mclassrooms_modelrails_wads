# frozen_string_literal: true

module UI
  # # Accordion
  #
  # A stack of native `<details>` disclosure rows. The browser owns the
  # show/hide and the keyboard (the summary is focusable; Enter/Space toggles),
  # so the base component needs no JavaScript.
  #
  # ## Use when
  # - Progressively disclosing independent sections (FAQs, settings groups).
  #
  # ## Accessibility contract
  # - **Guarantees:** native disclosure semantics, an AAA `focus-ring` on each
  #   summary, and a decorative (aria-hidden) chevron.
  # - **You supply:** a `title` per row and the content.
  #
  # ## Modes
  # Independent (default) · `exclusive: true` (one open at a time, via Stimulus).
  # @logical_path Data Display
  class AccordionComponentPreview < ViewComponent::Preview
    include UIHelper

    # Independent rows — opening one leaves the others untouched. No JavaScript.
    def default
    end

    # `exclusive: true` — opening one row closes the rest via the `accordion`
    # Stimulus controller (progressive enhancement; degrades to independent rows).
    def exclusive
    end

    # Rich block content via the slot API, with one row open on load.
    def rich_content
    end
  end
end
