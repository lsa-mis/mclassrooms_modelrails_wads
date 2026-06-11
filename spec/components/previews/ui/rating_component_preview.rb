# frozen_string_literal: true

module UI
  # # Rating
  #
  # A static, read-only star rating — fills `value` of `max` stars to display a
  # score. The whole control is one labelled graphic (`role="img"` + i18n
  # `aria-label`, e.g. "3 out of 5 stars") so AT announces the value; the star
  # glyphs themselves are decorative (`aria-hidden`). For an *interactive* score
  # the user sets, use `rating_input`.
  #
  # ## Use when
  # - You're displaying a fixed score the user can't change (a product's average
  #   rating, a past review's stars).
  #
  # ## Don't use when
  # - The user picks the value — use `ui :rating_input`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a single labelled graphic exposing the value to AT, decorative
  #   `aria-hidden` star glyphs, and filled stars on the AAA-tuned semantic
  #   `text-warning-icon` token (3:1 graphic contrast, WCAG 1.4.11).
  # - **You supply:** the `value:` to display and the `max:` star count.
  #
  # ## Related
  # `rating_input`
  # @logical_path Data Display
  class RatingComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Default — three of five stars filled; announces as "3 out of 5 stars".
    def default
    end

    # Full marks — every star filled on the semantic warning token.
    def full
    end

    # Custom scale — value of a larger max (a 10-star scale).
    def custom_scale
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — never substitute a raw color for the semantic token
    #
    # Filled stars must use the AAA-tuned `text-warning-icon` token, not a raw
    # Tailwind color like `text-yellow-400`. Raw colors bypass the theme's
    # graphic-contrast guarantees and dark-mode mapping. This scenario shows the
    # correct, hardened component.
    # @label Don't · raw color for filled stars
    def dont_raw_color
    end

    # @!endgroup
  end
end
