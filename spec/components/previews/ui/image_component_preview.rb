# frozen_string_literal: true

module UI
  # # Image
  #
  # A responsive `<img>` wrapper that forces an `alt` decision at the call site and
  # supports lazy loading, `srcset`/`sizes`, and intrinsic dimensions.
  #
  # ## Use when
  # - Rendering content imagery with lazy loading + responsive sources and an
  #   explicit alt-text decision.
  #
  # ## Don't use when
  # - The image is an icon inside a control — the control already names it.
  #
  # ## Accessibility contract
  # - **Guarantees:** `alt:` is required; invalid `loading:` falls back to `:lazy`.
  # - **You supply:** real `alt:` for meaningful images, `alt: ""` for decorative.
  #   `alt` is not a caption — use `figure` for those.
  class ImageComponentPreview < ViewComponent::Preview
    include UIHelper

    # A meaningful image with real alt text.
    def default
    end

    # Responsive sources + intrinsic dimensions.
    def responsive
    end

    # Decorative image — `alt: ""` so AT skips it.
    def decorative
    end

    # ## Don't — alt used as a caption
    #
    # `alt` should be a terse equivalent, not a long descriptive sentence. Stuffing a
    # caption into `alt` makes the screen-reader experience verbose and wrong. Use
    # `figure` + `figcaption` for captions and keep `alt` short.
    # @label Don't · alt as caption
    def dont_alt_as_caption
    end
  end
end
