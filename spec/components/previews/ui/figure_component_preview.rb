# frozen_string_literal: true

module UI
  # # Figure
  #
  # A semantic `<figure>` wrapping content with an optional `<figcaption>`. The
  # caption supplements the content; it does not replace the content's accessible name.
  #
  # ## Use when
  # - You have referenced content that benefits from a visible caption (captioned
  #   image, diagram, quoted block).
  #
  # ## Don't use when
  # - You're relying on the caption to describe an image that lacks `alt` — the
  #   image still needs its own `alt`.
  #
  # ## Accessibility contract
  # - **Guarantees:** semantic figure/figcaption; caption rendered only when given.
  #   Caption uses `text-text-muted` (AAA — same neutral as body in this token system).
  # - **You supply:** real `alt` on any inner image.
  # @logical_path Media
  class FigureComponentPreview < ViewComponent::Preview
    include UIHelper

    # An image with a caption.
    def default
    end

    # A figure with no caption.
    def no_caption
    end

    # ## Don't — caption used in place of alt
    #
    # This image has no `alt` and leans on the figcaption to describe it. The
    # figcaption is a supplement, not a substitute — the image still needs its own
    # `alt`. Give the image real alt text (or `alt: ""` if truly decorative).
    # @label Don't · caption replaces alt
    def dont_caption_replaces_alt
    end
  end
end
