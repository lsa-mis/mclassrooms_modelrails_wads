# frozen_string_literal: true

module UI
  # # Iframe
  #
  # A responsive embedded-frame wrapper (`<iframe>`), optionally aspect-ratio
  # constrained, with lazy loading and sandboxing on by default.
  #
  # ## Use when
  # - Embedding external content (a map, video, document, or third-party widget)
  #   with a responsive, sandboxed frame and an explicit accessible name.
  #
  # ## Don't use when
  # - The content is first-party imagery or video you control — use `image` or a
  #   native `<video>`; an iframe is for cross-document/embedded content.
  #
  # ## Accessibility contract
  # - **Guarantees:** `title:` is required and must be non-blank — every iframe
  #   carries an accessible name. Invalid `loading:` falls back to `:lazy`.
  # - **You supply:** a real `title:` describing the embedded content. Unlike an
  #   image there is no "decorative" iframe — a title-less iframe is a hard WCAG
  #   failure.
  class IframeComponentPreview < ViewComponent::Preview
    include UIHelper

    # A titled iframe embedding an external map.
    def default
    end

    # Aspect-ratio constrained (16/9) — the frame stays responsive at any width.
    def responsive
    end

    # ## Don't — iframe with no accessible name
    #
    # An iframe without a `title` (or with a blank one) is a hard WCAG failure:
    # assistive tech announces it as an unnamed "frame" with no idea what it holds.
    # This component fails loud on a blank title for exactly this reason — the
    # snippet below shows the wrong call shape (which would raise).
    # @label Don't · no title
    def dont_no_title
    end
  end
end
