# frozen_string_literal: true

module UI
  # # Carousel
  #
  # A slide carousel (WAI-ARIA APG "basic" pattern): prev/next + slide-picker dots,
  # all real `<button>`s with ≥44px targets. Autoplay (when `autoplay:` > 0) is
  # WCAG 2.2.2 compliant — a pause/play toggle, pause on hover/focus, and disabled
  # under `prefers-reduced-motion`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a labelled `role="group"` carousel region, per-slide
  #   `aria-roledescription="slide"` labels, ≥44px focusable controls with the
  #   `focus-ring` utility, and (with autoplay) a 2.2.2 pause mechanism that flips
  #   the live region to `polite` when stopped.
  # - **You supply:** an accessible `label:` and the slide content.
  # @logical_path Media
  class CarouselComponentPreview < ViewComponent::Preview
    include UIHelper

    # Manual carousel (no autoplay) with 3 slides — prev/next + dots.
    def default
    end

    # Autoplaying carousel (3s interval) with a pause/play toggle (WCAG 2.2.2).
    def autoplay
    end
  end
end
