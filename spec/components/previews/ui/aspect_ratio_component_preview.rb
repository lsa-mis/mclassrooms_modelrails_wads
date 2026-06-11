# frozen_string_literal: true

module UI
  # # Aspect Ratio
  #
  # A layout wrapper that constrains its slotted content to a fixed aspect ratio
  # (e.g. `16 / 9`) via the CSS `aspect-ratio` property. Purely presentational and
  # non-interactive — it frames media, it is never itself a target.
  #
  # ## Use when
  # - Embedding media that must hold a ratio regardless of width: a video `<iframe>`,
  #   a responsive `<img>`, a map, a thumbnail.
  #
  # ## Don't use when
  # - There is no content to frame — an empty ratio box reserves space for nothing.
  # - The content already has intrinsic dimensions you want to respect — let it size
  #   itself instead of clipping it to a forced ratio.
  #
  # ## Accessibility contract
  # - **Guarantees:** a presentational wrapper with no role, no tabindex, and no
  #   focus ring — it adds nothing for assistive tech to announce.
  # - **You supply:** slotted media that carries its own a11y (an `<img>` with `alt`,
  #   an `<iframe>` with `title`, etc.). The wrapper does not speak for it.
  # @logical_path Media
  class AspectRatioComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Widescreen 16:9 framing an image.
    def default
    end

    # A square (1:1) thumbnail.
    def square
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — an empty ratio box
    #
    # With no slotted content the wrapper reserves layout space for nothing and
    # announces nothing. Give it media to frame, or drop the wrapper entirely.
    # @label Don't · no content
    def dont_no_content
    end

    # @!endgroup
  end
end
