# frozen_string_literal: true

module UI
  # # Picture
  #
  # A `<picture>` element with art-direction / format-fallback `<source>`s and a
  # required base `<img>`. The browser picks the first matching `<source>`; the
  # `<img>` is the final fallback and carries the accessible name.
  #
  # ## Use when
  # - You need format fallbacks (AVIF/WebP → JPEG) or a different crop per viewport
  #   that `srcset`/`sizes` on a plain `<img>` can't express.
  #
  # ## Don't use when
  # - You only need resolution switching — a single `image` with `srcset:` is simpler.
  #
  # ## Accessibility contract
  # - **Guarantees:** `alt:` is required on the base `<img>`; `<source>`s carry no
  #   `alt`, so the name comes solely from the `<img>`. Invalid `loading:` → `:lazy`.
  # - **You supply:** real `alt:` for meaningful images, `alt: ""` for decorative.
  # @logical_path Media
  class PictureComponentPreview < ViewComponent::Preview
    include UIHelper

    # Art-directed sources — a wide crop on large screens, a narrow crop on small.
    def default
    end

    # Format fallback — AVIF, then WebP, then the JPEG base <img>.
    def formats
    end

    # ## Don't — base <img> without alt
    #
    # A `<picture>` has no accessible name unless its base `<img>` has `alt`.
    # `<source>`s never carry alt. Omitting `alt:` is a call-site error here (the
    # component requires it) — always pass real alt text, or `alt: ""` if decorative.
    # @label Don't · no alt
    def dont_no_alt
    end
  end
end
