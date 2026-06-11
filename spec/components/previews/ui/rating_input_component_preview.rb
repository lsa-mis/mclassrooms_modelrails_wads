# frozen_string_literal: true

module UI
  # # RatingInput
  #
  # A star rating input — a labelled `role="group"` of star `<button>`s plus a
  # hidden input that carries the value inside a form. The `rating` Stimulus
  # controller previews on hover and commits on click.
  #
  # ## Use when
  # - You need a quick 1..max star score (a review, a satisfaction rating), posted
  #   in a form (`name:`) or sent straight to an endpoint (`url:`).
  #
  # ## Don't use when
  # - The scale isn't ordinal stars or needs half/decimal precision — use a
  #   `ui :select` or a numeric input.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named star group (`role="group"` + `aria-label`), each star
  #   a labelled `<button>` with a >=44px target (AAA 2.5.5) even though the visual
  #   star is 24px, filled stars on the AAA-tuned semantic warning token (3:1 graphic
  #   contrast, WCAG 1.4.11), and a hidden input carrying the value in a form.
  # - **You supply:** an optional group `label:`, the initial `value:`, `max:`, and
  #   either `name:` (form post) or `url:` (direct submit).
  #
  # ## Related
  # `rating`
  # @logical_path Forms & Inputs
  class RatingInputComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Default — an empty 5-star rating with the default "Rating" group name.
    def default
    end

    # With a value — three of five stars filled (semantic warning token).
    def with_value
    end

    # In a form — a `name:` emits the hidden input so the score posts.
    def in_a_form
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — never substitute a raw color for the semantic token
    #
    # Filled stars must use the AAA-tuned `text-warning-icon` token, not a raw
    # Tailwind color like `text-yellow-400`. Raw colors bypass the theme's
    # graphic-contrast guarantees and dark-mode mapping. This scenario shows the
    # correct, hardened component for contrast.
    # @label Don't · raw color for filled stars
    def dont_raw_color
    end

    # @!endgroup
  end
end
